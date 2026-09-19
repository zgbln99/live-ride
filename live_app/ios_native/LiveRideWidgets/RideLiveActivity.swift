import ActivityKit
import SwiftUI
import WidgetKit

/// Live Ride's colours, kept in step with the Flutter theme.
private enum LRColor {
    static let accent = Color(red: 0.0, green: 0.75, blue: 0.85)
    static let alert = Color(red: 0.88, green: 0.17, blue: 0.13)
    static let muted = Color.white.opacity(0.55)
}

/// The Lock Screen and Dynamic Island presentation of a ride in progress.
@available(iOS 16.2, *)
struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            LockScreenView(
                attributes: context.attributes,
                state: context.state
            )
            .activityBackgroundTint(Color.black.opacity(0.82))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandStat(
                        value: context.state.speed,
                        unit: context.state.speedUnit,
                        label: "SPEED"
                    )
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandStat(
                        value: context.state.distance,
                        unit: context.state.distanceUnit,
                        label: "DISTANCE"
                    )
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.paused ? "PAUSED" : context.attributes.title)
                        .font(.caption2.weight(.heavy))
                        .foregroundColor(context.state.paused ? LRColor.muted : LRColor.accent)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.hasManeuver {
                        ManeuverRow(state: context.state, compact: true)
                    } else {
                        HStack(spacing: 18) {
                            IslandStat(
                                value: context.state.elapsed,
                                unit: "",
                                label: "ELAPSED"
                            )
                            if context.state.heartRate != "--" {
                                IslandStat(
                                    value: context.state.heartRate,
                                    unit: "bpm",
                                    label: "HEART RATE"
                                )
                            }
                            IslandStat(
                                value: context.state.ascent,
                                unit: context.state.ascentUnit,
                                label: "ASCENT"
                            )
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.paused ? "pause.fill" : "bicycle")
                    .foregroundColor(LRColor.accent)
            } compactTrailing: {
                Text(context.state.speed)
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundColor(.white)
            } minimal: {
                Image(systemName: "bicycle")
                    .foregroundColor(LRColor.accent)
            }
            .keylineTint(LRColor.accent)
        }
    }
}

/// The card on the Lock Screen.
@available(iOS 16.2, *)
private struct LockScreenView: View {
    let attributes: RideActivityAttributes
    let state: RideActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if state.hasManeuver {
                ManeuverRow(state: state, compact: false)
                Divider().overlay(Color.white.opacity(0.12))
            }
            HStack(alignment: .bottom, spacing: 0) {
                Stat(value: state.speed, unit: state.speedUnit, label: "SPEED")
                Spacer(minLength: 8)
                Stat(
                    value: state.distance,
                    unit: state.distanceUnit,
                    label: "DISTANCE"
                )
                Spacer(minLength: 8)
                Stat(value: state.elapsed, unit: "", label: "ELAPSED")
                if state.heartRate != "--" {
                    Spacer(minLength: 8)
                    Stat(value: state.heartRate, unit: "bpm", label: "HR")
                }
            }
        }
        .padding(16)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "bicycle")
                .font(.footnote.weight(.bold))
                .foregroundColor(LRColor.accent)
            Text("LIVE RIDE")
                .font(.system(size: 10, weight: .black))
                .tracking(1.8)
                .foregroundColor(LRColor.accent)
            Text(attributes.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(LRColor.muted)
                .lineLimit(1)
            Spacer(minLength: 4)
            if state.paused {
                Badge(text: "PAUSED", color: LRColor.muted)
            } else if state.live {
                Badge(text: "LIVE", color: LRColor.alert)
            }
        }
    }
}

/// The next turn, shown in place of nothing when navigating.
@available(iOS 16.2, *)
private struct ManeuverRow: View {
    let state: RideActivityAttributes.ContentState
    let compact: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: state.maneuverSymbol)
                .font(.system(size: compact ? 20 : 28, weight: .semibold))
                .foregroundColor(state.offRoute ? LRColor.alert : .white)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.maneuverDistance)
                    .font(.system(size: compact ? 18 : 24, weight: .heavy))
                    .monospacedDigit()
                    .foregroundColor(.white)
                Text(state.offRoute ? "OFF ROUTE" : state.maneuver)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(state.offRoute ? LRColor.alert : LRColor.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

@available(iOS 16.2, *)
private struct Stat: View {
    let value: String
    let unit: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .black))
                .tracking(1.0)
                .foregroundColor(LRColor.muted)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 22, weight: .heavy))
                    .monospacedDigit()
                    .foregroundColor(.white)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(LRColor.muted)
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

@available(iOS 16.2, *)
private struct IslandStat: View {
    let value: String
    let unit: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 7, weight: .black))
                .tracking(0.8)
                .foregroundColor(LRColor.muted)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .heavy))
                    .monospacedDigit()
                    .foregroundColor(.white)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(LRColor.muted)
                }
            }
        }
    }
}

@available(iOS 16.2, *)
private struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 8, weight: .black))
            .tracking(1.0)
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(color, lineWidth: 1)
            )
    }
}
