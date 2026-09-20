import Combine
import Foundation
import HealthKit
import WatchConnectivity

/// Sesja treningowa na zegarku: mierzy tętno i wysyła je do telefonu.
///
/// `HKWorkoutSession` jest tu obowiązkowy, a nie kosmetyczny. Bez niej
/// watchOS usypia aplikację po kilkunastu sekundach od zgaszenia ekranu
/// i czujnik przestaje próbkować częściej niż co kilka minut — czyli
/// dokładnie wtedy, kiedy jedzie się rowerem.
final class WatchWorkoutSession: NSObject, ObservableObject {
    static let shared = WatchWorkoutSession()

    @Published private(set) var heartRate: Int?
    @Published private(set) var isRunning = false
    @Published private(set) var statusText = "Tętno na żywo dla Live Ride"

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private override init() {
        super.init()
        activateConnectivity()
    }

    private func activateConnectivity() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func start() {
        guard HKHealthStore.isHealthDataAvailable() else {
            statusText = "HealthKit niedostępny"
            return
        }
        // Prosimy o dokładnie dwie rzeczy: prawo zapisu treningu i odczyt
        // tętna. Nic więcej nie jest do tego potrzebne.
        let share: Set = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.activitySummaryType(),
        ]
        store.requestAuthorization(toShare: share, read: read) { [weak self] granted, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                granted ? self.beginSession() : self.fail("Brak zgody na HealthKit")
            }
        }
    }

    private func beginSession() {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .cycling
        configuration.locationType = .outdoor

        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: store,
                workoutConfiguration: configuration
            )
            session.delegate = self
            builder.delegate = self

            let start = Date()
            session.startActivity(with: start)
            builder.beginCollection(withStart: start) { [weak self] _, error in
                DispatchQueue.main.async {
                    if let error {
                        self?.fail(error.localizedDescription)
                    } else {
                        self?.isRunning = true
                        self?.statusText = "Nadaje do telefonu"
                        self?.send(["streaming": true])
                    }
                }
            }
            self.session = session
            self.builder = builder
        } catch {
            fail(error.localizedDescription)
        }
    }

    func stop() {
        let finishedAt = Date()
        session?.end()
        builder?.endCollection(withEnd: finishedAt) { [weak self] _, _ in
            self?.builder?.finishWorkout { _, _ in }
        }
        session = nil
        builder = nil
        isRunning = false
        heartRate = nil
        statusText = "Zatrzymane"
        send(["streaming": false])
    }

    private func fail(_ message: String) {
        isRunning = false
        statusText = message
    }

    /// Wysyła próbkę do telefonu.
    ///
    /// `sendMessage` tylko wtedy, gdy telefon słucha — inaczej
    /// `updateApplicationContext`, które przetrwa chwilę bez łączności
    /// i dowiezie OSTATNI stan. Kolejkowanie starych próbek nie ma sensu:
    /// tętno sprzed trzydziestu sekund nikogo nie interesuje.
    private func send(_ payload: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            try? session.updateApplicationContext(payload)
        }
    }
}

extension WatchWorkoutSession: HKWorkoutSessionDelegate {
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        DispatchQueue.main.async {
            self.isRunning = toState == .running
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { self.fail(error.localizedDescription) }
    }
}

extension WatchWorkoutSession: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        guard
            let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
            collectedTypes.contains(heartRateType),
            let statistics = workoutBuilder.statistics(for: heartRateType),
            let quantity = statistics.mostRecentQuantity()
        else { return }

        let unit = HKUnit.count().unitDivided(by: .minute())
        let bpm = Int(quantity.doubleValue(for: unit).rounded())
        guard bpm >= 25, bpm <= 260 else { return }

        DispatchQueue.main.async {
            self.heartRate = bpm
            // Znacznik czasu jedzie z próbką: telefon musi umieć odróżnić
            // pomiar sprzed sekundy od ostatniego, który dotarł przed
            // utratą łączności.
            self.send([
                "bpm": bpm,
                "at": Int(Date().timeIntervalSince1970 * 1000),
                "streaming": true,
            ])
        }
    }
}

extension WatchWorkoutSession: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    /// Telefon prosi o start albo stop sesji.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let command = message["command"] as? String else { return }
        DispatchQueue.main.async {
            switch command {
            case "start": self.start()
            case "stop": self.stop()
            default: break
            }
        }
    }
}
