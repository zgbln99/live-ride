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
                        label: "PRĘDKOŚĆ"
                    )
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandStat(
                        value: context.state.distance,
                        unit: context.state.distanceUnit,
                        label: "DYSTANS"
                    )
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(
                        context.state.paused
                            ? context.state.pauseBadge
                            : context.attributes.title
                    )
                    .font(.caption2.weight(.heavy))
                    .foregroundColor(
                        context.state.paused ? LRColor.muted : LRColor.accent
                    )
                    .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        if context.state.hasManeuver {
                            ManeuverRow(state: context.state, compact: true)
                        } else {
                            HStack(spacing: 18) {
                                IslandStat(
                                    value: context.state.elapsed,
                                    unit: "",
                                    label: "CZAS"
                                )
                                if context.state.heartRate != "--" {
                                    IslandStat(
                                        value: context.state.heartRate,
                                        unit: "bpm",
                                        label: "TĘTNO"
                                    )
                                }
                                IslandStat(
                                    value: context.state.ascent,
                                    unit: context.state.ascentUnit,
                                    label: "PRZEWYŻSZENIE"
                                )
                            }
                        }
                        if context.state.navigating {
                            ProgressLine(fraction: context.state.routeProgress)
                        }
                    }
                }
            } compactLeading: {
                // Ikona, nie tekst: szerokość jest stała niezależnie od stanu.
                Image(systemName: context.state.compactSymbol)
                    .foregroundColor(
                        context.state.offRoute
                            ? LRColor.alert
                            : context.state.paused ? LRColor.muted : LRColor.accent
                    )
            } compactTrailing: {
                // Liczba całkowita w polu o z góry zarezerwowanej szerokości.
                //
                // Wcześniej szła tu prędkość z częścią dziesiętną — „9.8",
                // „31.4", „0.0" — czyli za każdym razem inna liczba znaków.
                // Wyspa ma kilkadziesiąt punktów szerokości, więc każda taka
                // zmiana przesuwała cały układ i wyglądała jak usterka.
                Text(context.state.speedCompact)
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(minWidth: 26, alignment: .trailing)
            } minimal: {
                Image(systemName: context.state.compactSymbol)
                    .foregroundColor(
                        context.state.paused ? LRColor.muted : LRColor.accent
                    )
            }
            .keylineTint(LRColor.accent)
        }
    }
}

/// Karta na ekranie blokady.
///
/// Podczas nawigacji pokazuje TRASĘ, a nie tylko liczby: rowerzysta, który
/// odblokowuje telefon, żeby zobaczyć, gdzie jest na trasie, traci równowagę
/// i czas. Bez wczytanej trasy mapka nie pojawia się w ogóle — pusty
/// prostokąt wyglądałby jak usterka, a metryki są wtedy wszystkim, co mamy.
@available(iOS 16.2, *)
private struct LockScreenView: View {
    let attributes: RideActivityAttributes
    let state: RideActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            header
            if state.hasManeuver {
                ManeuverRow(state: state, compact: false)
            }
            if state.hasRoute {
                RouteStrip(state: state)
            }
            if state.hasManeuver || state.hasRoute {
                Divider().overlay(Color.white.opacity(0.12))
            }
            metrics
        }
        .padding(16)
    }

    private var metrics: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Stat(value: state.speed, unit: state.speedUnit, label: "PRĘDKOŚĆ")
            Spacer(minLength: 8)
            Stat(
                value: state.distance,
                unit: state.distanceUnit,
                label: "DYSTANS"
            )
            Spacer(minLength: 8)
            if state.navigating && !state.remainingDistance.isEmpty {
                Stat(
                    value: state.remainingDistance,
                    unit: state.distanceUnit,
                    label: "DO METY"
                )
            } else {
                Stat(value: state.elapsed, unit: "", label: "CZAS")
            }
            if state.heartRate != "--" {
                Spacer(minLength: 8)
                Stat(value: state.heartRate, unit: "bpm", label: "TĘTNO")
            }
        }
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
            if state.offRoute {
                Badge(text: "POZA TRASĄ", color: LRColor.alert)
            } else if state.paused {
                Badge(text: state.pauseBadge, color: LRColor.muted)
            } else if state.live {
                Badge(text: "LIVE", color: LRColor.alert)
            }
        }
    }
}

/// Kształt trasy z zaznaczoną pozycją zawodnika.
///
/// Nie jest to mapa i nie udaje mapy: nie ma kafelków, nazw ani skali. Jest
/// kształtem drogi — tym, co rowerzysta rozpoznaje jednym spojrzeniem, bo sam
/// ją zaplanował. Przejechane jest mocne i ciągłe, pozostałe przygaszone;
/// ta sama zasada co na mapie w aplikacji, gdzie plan jest przerywany.
@available(iOS 16.2, *)
private struct RouteStrip: View {
    let state: RideActivityAttributes.ContentState

    private static let height: CGFloat = 46

    var body: some View {
        Canvas { context, size in
            let points = state.routePoints
            guard points.count > 1 else { return }

            // Kształt zachowuje proporcje oryginału. Rozciągnięty na całą
            // szerokość wyglądałby jak inna droga.
            let inset: CGFloat = 4
            let box = CGSize(
                width: max(size.width - inset * 2, 1),
                height: max(size.height - inset * 2, 1)
            )
            let scale = min(box.width, box.height)
            let originX = inset + (box.width - scale) / 2
            let originY = inset + (box.height - scale) / 2
            let place: (CGPoint) -> CGPoint = { point in
                CGPoint(
                    x: originX + point.x * scale,
                    y: originY + point.y * scale
                )
            }

            var full = Path()
            full.addLines(points.map(place))
            context.stroke(
                full,
                with: .color(Color.white.opacity(0.28)),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            )

            // Przejechana część: tyle punktów, ile odpowiada postępowi.
            let progress = min(max(state.routeProgress, 0), 1)
            let ridden = Int((Double(points.count - 1) * progress).rounded())
            if ridden >= 1 {
                var done = Path()
                done.addLines(points.prefix(ridden + 1).map(place))
                context.stroke(
                    done,
                    with: .color(state.offRoute ? LRColor.alert : LRColor.accent),
                    style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round)
                )
            }

            // Start i meta — małe, żeby nie przykryły samej trasy.
            context.fill(
                Path(ellipseIn: CGRect(
                    origin: CGPoint(
                        x: place(points[0]).x - 2.5,
                        y: place(points[0]).y - 2.5
                    ),
                    size: CGSize(width: 5, height: 5)
                )),
                with: .color(Color.white.opacity(0.5))
            )
            let finish = place(points[points.count - 1])
            context.stroke(
                Path(ellipseIn: CGRect(
                    x: finish.x - 3.5,
                    y: finish.y - 3.5,
                    width: 7,
                    height: 7
                )),
                with: .color(Color.white.opacity(0.7)),
                lineWidth: 1.4
            )

            // Zawodnik: pełne kółko w białej obwódce, widoczne także na linii.
            let hereIndex = min(max(ridden, 0), points.count - 1)
            let here = place(points[hereIndex])
            context.fill(
                Path(ellipseIn: CGRect(
                    x: here.x - 5,
                    y: here.y - 5,
                    width: 10,
                    height: 10
                )),
                with: .color(.white)
            )
            context.fill(
                Path(ellipseIn: CGRect(
                    x: here.x - 3.2,
                    y: here.y - 3.2,
                    width: 6.4,
                    height: 6.4
                )),
                with: .color(state.offRoute ? LRColor.alert : LRColor.accent)
            )
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
    }
}

/// Pasek postępu trasy dla rozwiniętej wyspy.
@available(iOS 16.2, *)
private struct ProgressLine: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.22))
                Capsule()
                    .fill(LRColor.accent)
                    .frame(
                        width: geometry.size.width * min(max(fraction, 0), 1)
                    )
            }
        }
        .frame(height: 3)
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
                // Instrukcja przychodzi gotowa i po polsku — widget niczego
                // nie tłumaczy, żeby nie mógł powiedzieć czegoś innego niż
                // ekran jazdy.
                Text(state.offRoute ? "POZA TRASĄ" : state.maneuver)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(state.offRoute ? LRColor.alert : .white)
                    .lineLimit(1)
                if !compact && !state.offRoute && !state.maneuverStreet.isEmpty {
                    Text(state.maneuverStreet)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(LRColor.muted)
                        .lineLimit(1)
                }
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
