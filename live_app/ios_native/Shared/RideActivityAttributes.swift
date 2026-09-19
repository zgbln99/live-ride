import ActivityKit
import Foundation

/// The contract between the Live Ride app and its Lock Screen widget.
///
/// This file is compiled into both targets, so there is exactly one
/// definition of what a ride looks like on the Lock Screen. Every value is a
/// preformatted string: the Flutter side already knows the rider's units, and
/// a widget that formatted numbers itself could disagree with the handlebar.
@available(iOS 16.2, *)
public struct RideActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var speed: String
        public var speedUnit: String
        public var distance: String
        public var distanceUnit: String
        public var elapsed: String
        public var heartRate: String
        public var ascent: String
        public var ascentUnit: String
        public var paused: Bool
        /// „AUTO PAUZA" albo „PAUZA" — puste, gdy jazda trwa.
        ///
        /// Etykietę składa Flutter, bo tylko on wie, czy postój wykrył
        /// licznik, czy nacisnął go rowerzysta.
        public var pauseLabel: String
        public var live: Bool
        public var maneuver: String
        public var maneuverDistance: String
        public var maneuverSymbol: String
        public var offRoute: Bool

        public init(
            speed: String = "0.0",
            speedUnit: String = "km/h",
            distance: String = "0.00",
            distanceUnit: String = "km",
            elapsed: String = "00:00",
            heartRate: String = "--",
            ascent: String = "0",
            ascentUnit: String = "m",
            paused: Bool = false,
            pauseLabel: String = "",
            live: Bool = false,
            maneuver: String = "",
            maneuverDistance: String = "",
            maneuverSymbol: String = "location.north.line",
            offRoute: Bool = false
        ) {
            self.speed = speed
            self.speedUnit = speedUnit
            self.distance = distance
            self.distanceUnit = distanceUnit
            self.elapsed = elapsed
            self.heartRate = heartRate
            self.ascent = ascent
            self.ascentUnit = ascentUnit
            self.paused = paused
            self.pauseLabel = pauseLabel
            self.live = live
            self.maneuver = maneuver
            self.maneuverDistance = maneuverDistance
            self.maneuverSymbol = maneuverSymbol
            self.offRoute = offRoute
        }

        /// Builds a state from the dictionary the Flutter method channel sends.
        /// Missing keys fall back to the defaults rather than failing the
        /// update, because a Lock Screen card is never worth crashing a ride.
        public init(payload: [String: Any]) {
            self.init(
                speed: payload["speed"] as? String ?? "0.0",
                speedUnit: payload["speedUnit"] as? String ?? "km/h",
                distance: payload["distance"] as? String ?? "0.00",
                distanceUnit: payload["distanceUnit"] as? String ?? "km",
                elapsed: payload["elapsed"] as? String ?? "00:00",
                heartRate: payload["heartRate"] as? String ?? "--",
                ascent: payload["ascent"] as? String ?? "0",
                ascentUnit: payload["ascentUnit"] as? String ?? "m",
                paused: payload["paused"] as? Bool ?? false,
                pauseLabel: payload["pauseLabel"] as? String ?? "",
                live: payload["live"] as? Bool ?? false,
                maneuver: payload["maneuver"] as? String ?? "",
                maneuverDistance: payload["maneuverDistance"] as? String ?? "",
                maneuverSymbol: payload["maneuverSymbol"] as? String
                    ?? "location.north.line",
                offRoute: payload["offRoute"] as? Bool ?? false
            )
        }

        /// Co napisać na odznace postoju: etykieta z aplikacji, a gdy jej
        /// nie ma (starsza wersja aplikacji, świeżo po aktualizacji) — słowo
        /// zastępcze, żeby odznaka nigdy nie była pusta.
        public var pauseBadge: String {
            pauseLabel.isEmpty ? "PAUZA" : pauseLabel
        }

        /// True when there is a turn worth showing instead of the ride stats.
        public var hasManeuver: Bool {
            !maneuver.isEmpty && !maneuverDistance.isEmpty
        }
    }

    public var riderName: String
    public var title: String
    public var navigating: Bool

    public init(riderName: String, title: String, navigating: Bool) {
        self.riderName = riderName
        self.title = title
        self.navigating = navigating
    }
}
