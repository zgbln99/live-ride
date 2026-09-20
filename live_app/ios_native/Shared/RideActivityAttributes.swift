import ActivityKit
import CoreGraphics
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
        public var maneuverStreet: String
        public var offRoute: Bool

        /// Prędkość bez części dziesiętnej, dla Dynamic Island.
        ///
        /// Wyspa ma kilkadziesiąt punktów szerokości. „9.8" i „31.4" to różna
        /// liczba znaków, więc przy każdej zmianie układ przeskakiwał —
        /// stąd osobne, krótkie pole zamiast skracania `speed` na miejscu.
        public var speedCompact: String

        /// Kształt trasy w kwadracie jednostkowym: „x,y;x,y" w tysięcznych.
        ///
        /// Przychodzi osobnym wywołaniem i tylko przy zmianie trasy; most
        /// dokłada go do każdej kolejnej aktualizacji, żeby widget nigdy nie
        /// został bez geometrii.
        public var routeShape: String
        public var routeAspect: Double

        /// Postęp na trasie, 0–1. Tyle wystarczy, żeby narysować przejechaną
        /// część ścieżki i postawić znacznik zawodnika.
        public var routeProgress: Double
        public var remainingDistance: String
        public var navigating: Bool

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
            maneuverStreet: String = "",
            speedCompact: String = "0",
            routeShape: String = "",
            routeAspect: Double = 1,
            routeProgress: Double = 0,
            remainingDistance: String = "",
            navigating: Bool = false,
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
            self.maneuverStreet = maneuverStreet
            self.speedCompact = speedCompact
            self.routeShape = routeShape
            self.routeAspect = routeAspect
            self.routeProgress = routeProgress
            self.remainingDistance = remainingDistance
            self.navigating = navigating
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
                maneuverStreet: payload["maneuverStreet"] as? String ?? "",
                speedCompact: payload["speedCompact"] as? String ?? "0",
                routeShape: payload["routeShape"] as? String ?? "",
                routeAspect: payload["routeAspect"] as? Double ?? 1,
                routeProgress: payload["routeProgress"] as? Double ?? 0,
                remainingDistance: payload["remainingDistance"] as? String ?? "",
                navigating: payload["navigating"] as? Bool ?? false,
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

        /// Ikona dla zwiniętej wyspy i trybu minimalnego.
        ///
        /// Ikona, a nie tekst: symbol ma zawsze tę samą szerokość, więc układ
        /// nie przeskakuje przy zmianie stanu. Trzy stany, które rowerzysta
        /// naprawdę rozróżnia rzutem oka — jadę, stoję, zgubiłem trasę.
        public var compactSymbol: String {
            if offRoute { return "exclamationmark.triangle.fill" }
            if paused { return "pause.fill" }
            return "bicycle"
        }

        /// Czy da się narysować trasę.
        ///
        /// Dwa punkty to jeszcze nie kształt, a pusty prostokąt na ekranie
        /// blokady wygląda jak usterka. Bez geometrii widget pokazuje zwykły
        /// ekran przejazdu z metrykami.
        public var hasRoute: Bool {
            routeShape.count > 8
        }

        /// Kształt trasy jako punkty w kwadracie jednostkowym.
        ///
        /// Dekodowanie po stronie widgetu, bo tylko on wie, na jaki prostokąt
        /// je przeskalować — a przesyłanie gotowych pikseli wymagałoby
        /// znajomości rozmiaru karty po stronie aplikacji.
        public var routePoints: [CGPoint] {
            routeShape.split(separator: ";").compactMap { pair in
                let parts = pair.split(separator: ",")
                guard parts.count == 2,
                      let x = Double(parts[0]),
                      let y = Double(parts[1])
                else { return nil }
                return CGPoint(x: x / 1000, y: y / 1000)
            }
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
