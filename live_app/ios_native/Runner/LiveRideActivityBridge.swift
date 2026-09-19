import Flutter
import Foundation
import UIKit

#if canImport(ActivityKit)
import ActivityKit
#endif

/// Bridges the Flutter `live_ride/live_activity` method channel to ActivityKit.
///
/// The Dart side decides what to show and when; this only starts, updates and
/// ends the activity. Every failure is reported back rather than thrown at the
/// rider: a ride must never depend on the Lock Screen card working.
final class LiveRideActivityBridge: NSObject {
    private static let channelName = "live_ride/live_activity"

    /// Boxed because a stored property cannot carry an availability
    /// annotation, and Activity<…> only exists on iOS 16.2+.
    private var boxedActivity: Any?

    @discardableResult
    static func register(with messenger: FlutterBinaryMessenger) -> LiveRideActivityBridge {
        let bridge = LiveRideActivityBridge()
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
        channel.setMethodCallHandler { call, result in
            bridge.handle(call, result: result)
        }
        return bridge
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isSupported":
            result(isSupported)
        case "start":
            start(arguments: call.arguments as? [String: Any] ?? [:], result: result)
        case "update":
            update(arguments: call.arguments as? [String: Any] ?? [:], result: result)
        case "end":
            end(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private var isSupported: Bool {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            return ActivityAuthorizationInfo().areActivitiesEnabled
        }
        #endif
        return false
    }

    // MARK: - Activity lifecycle

    private func start(arguments: [String: Any], result: @escaping FlutterResult) {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                result(
                    FlutterError(
                        code: "disabled",
                        message: "Live Activities are switched off for Live Ride in Settings.",
                        details: nil
                    )
                )
                return
            }

            // A leftover activity from a crashed session would otherwise sit
            // on the Lock Screen for hours.
            endAllActivities()

            let attributes = RideActivityAttributes(
                riderName: arguments["riderName"] as? String ?? "Rider",
                title: arguments["title"] as? String ?? "Live Ride",
                navigating: arguments["navigating"] as? Bool ?? false
            )
            let state = RideActivityAttributes.ContentState()

            do {
                let activity = try Activity<RideActivityAttributes>.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: staleDate()),
                    pushType: nil
                )
                boxedActivity = activity
                result(nil)
            } catch {
                result(
                    FlutterError(
                        code: "start_failed",
                        message: error.localizedDescription,
                        details: nil
                    )
                )
            }
            return
        }
        #endif
        result(
            FlutterError(
                code: "unsupported",
                message: "Live Activities need iOS 16.2 or later.",
                details: nil
            )
        )
    }

    private func update(arguments: [String: Any], result: @escaping FlutterResult) {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            guard let activity = boxedActivity as? Activity<RideActivityAttributes> else {
                result(nil)
                return
            }
            let state = RideActivityAttributes.ContentState(payload: arguments)
            Task {
                await activity.update(
                    ActivityContent(state: state, staleDate: staleDate())
                )
            }
            result(nil)
            return
        }
        #endif
        result(nil)
    }

    private func end(result: @escaping FlutterResult) {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            let activity = boxedActivity as? Activity<RideActivityAttributes>
            boxedActivity = nil
            Task {
                if let activity = activity {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
                endAllActivities()
            }
            result(nil)
            return
        }
        #endif
        result(nil)
    }

    /// Marks the card stale if no update arrives, so a Lock Screen glance
    /// never shows a speed from ten minutes ago as if it were current.
    @available(iOS 16.2, *)
    private func staleDate() -> Date {
        Date().addingTimeInterval(120)
    }

    @available(iOS 16.2, *)
    private func endAllActivities() {
        for activity in Activity<RideActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
