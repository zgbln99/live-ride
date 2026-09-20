import SwiftUI

/// Live Ride na Apple Watch.
///
/// Zegarek nie jest tu drugim licznikiem. Ma jedno zadanie: utrzymać sesję
/// treningową HealthKit, żeby czujnik na nadgarstku mierzył tętno CO SEKUNDĘ
/// i nadawał je przy zgaszonym ekranie, a potem wysyłać je do telefonu.
///
/// To jedyna droga do prawdziwego tętna na żywo z Apple Watch. Czytanie
/// HealthKit z iPhone'a daje próbki, które zegarek zapisał kiedyś —
/// z opóźnieniem liczonym w dziesiątkach sekund, a przy zablokowanym ekranie
/// w minutach. Na liczniku rowerowym taka wartość nie jest tętnem.
@main
struct LiveRideWatchApp: App {
    @StateObject private var session = WatchWorkoutSession.shared

    var body: some Scene {
        WindowGroup {
            WatchRideView()
                .environmentObject(session)
        }
    }
}

struct WatchRideView: View {
    @EnvironmentObject private var session: WatchWorkoutSession

    var body: some View {
        VStack(spacing: 8) {
            Text("LIVE RIDE")
                .font(.system(size: 12, weight: .black))
                .kerning(2)
                .foregroundStyle(.secondary)

            if let bpm = session.heartRate {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(bpm)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("bpm")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(session.isRunning ? "—" : "GOTOWY")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            Text(session.statusText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Jazdę zaczyna się na telefonie. Przycisk na zegarku jest dla
            // sytuacji, w której telefon leży w kieszeni i nie chce się go
            // wyciągać — nie dla dublowania startu.
            Button(session.isRunning ? "ZATRZYMAJ" : "START") {
                session.isRunning ? session.stop() : session.start()
            }
            .buttonStyle(.borderedProminent)
            .font(.system(size: 13, weight: .bold))
        }
        .padding(.horizontal, 6)
    }
}
