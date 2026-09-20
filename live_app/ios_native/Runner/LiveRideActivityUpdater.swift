import Foundation

#if canImport(ActivityKit)
import ActivityKit

/// Kolejka aktualizacji Live Activity — jedna na całą aktywność.
///
/// Trzy problemy, których nie da się rozwiązać osobno:
///
///  1. **Wyścig.** Każda aktualizacja szła wcześniej we własnym `Task {}`,
///     a te kończą się w dowolnej kolejności. Migawka sprzed sekundy potrafiła
///     nadpisać świeższą i ekran blokady pokazywał cofnięty dystans.
///
///  2. **Zaległa kolejka.** Przy chwilowym spowolnieniu ActivityKit rosła
///     kolejka zadań, z których każde niosło stan już nieaktualny. Wyspa
///     „odtwarzała" wtedy ostatnie kilkanaście sekund zamiast pokazywać teraz.
///
///  3. **Budżet.** System ogranicza częstotliwość aktualizacji. Przebijanie
///     go metrykami sprawia, że nie przechodzi ta jedna, na której zależy —
///     zmiana stanu na „POSTÓJ" albo nowy manewr.
///
/// Rozwiązanie jest jedno: aktor z JEDNYM oczekującym stanem. Nowy stan
/// nadpisuje poprzedni zamiast ustawiać się za nim w kolejce, więc zawsze
/// wysyłamy to, co jest teraz, i nigdy nie wysyłamy dwóch rzeczy naraz.
///
/// Stan jest też ZŁOŻONY, nie zastępowany: kształt trasy przychodzi raz i
/// dokłada się do kolejnych aktualizacji metryk. Dzięki temu widget nigdy nie
/// zostaje bez geometrii, a geometria nie jedzie po sieci co sekundę.
@available(iOS 16.2, *)
actor LiveRideActivityUpdater {
    /// Najkrótszy odstęp między zwykłymi aktualizacjami.
    ///
    /// Metryki zmieniają się co chwilę, a ekran blokady i tak odświeża się
    /// rzadziej niż oko zdąży zauważyć. Zmiany stanu tej granicy nie dotyczą.
    private static let quietInterval: TimeInterval = 0.9

    private let activity: Activity<RideActivityAttributes>

    /// Ostatni pełny stan — podstawa do składania kolejnych.
    private var current: RideActivityAttributes.ContentState

    /// Stan czekający na wysłanie. Zawsze najwyżej jeden: nowy nadpisuje stary.
    private var pending: RideActivityAttributes.ContentState?
    private var pendingIsUrgent = false

    private var pumping = false
    private var lastPush = Date.distantPast

    init(
        activity: Activity<RideActivityAttributes>,
        initial: RideActivityAttributes.ContentState
    ) {
        self.activity = activity
        self.current = initial
    }

    /// Przyjmuje nowy zestaw pól z aplikacji.
    ///
    /// `payload` może nieść tylko część pól — reszta zostaje z poprzedniego
    /// stanu. Tak właśnie przychodzi geometria trasy: osobno i rzadko.
    func submit(payload: [String: Any], urgent: Bool) {
        current = merged(payload: payload)
        pending = current
        pendingIsUrgent = pendingIsUrgent || urgent
        startPumping()
    }

    /// Wysyła to, co czeka, i nic poza tym.
    ///
    /// Pętla, a nie rekurencja: po zakończeniu wysyłki sprawdzamy, czy w
    /// międzyczasie nie pojawił się nowszy stan. Jeśli tak, wysyłamy go
    /// zamiast tego, co właśnie poszło — i tak dalej, aż zrobi się cicho.
    private func startPumping() {
        guard !pumping else { return }
        pumping = true
        Task { await pump() }
    }

    private func pump() async {
        defer { pumping = false }

        while let next = pending {
            let urgent = pendingIsUrgent
            pending = nil
            pendingIsUrgent = false

            // Zwykła aktualizacja czeka na swoje okno. Pilna nie czeka wcale —
            // ale nadal przechodzi przez tę samą kolejkę, więc nie wyprzedzi
            // niczego, co już leci.
            if !urgent {
                let since = Date().timeIntervalSince(lastPush)
                if since < Self.quietInterval {
                    let wait = Self.quietInterval - since
                    try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                    // Po odczekaniu może już być coś nowszego — wtedy tamto
                    // wygrywa, a to, co trzymamy, jest do wyrzucenia.
                    if pending != nil { continue }
                }
            }

            lastPush = Date()
            await activity.update(
                ActivityContent(state: next, staleDate: Self.staleDate())
            )
        }
    }

    /// Składa nowy stan ze starego i tego, co przyszło.
    ///
    /// Brak klucza znaczy „bez zmian", a nie „wyzeruj". To jest cała różnica
    /// między aktualizacją częściową a nadpisaniem ekranu blokady zerami przy
    /// każdej zmianie prędkości.
    private func merged(payload: [String: Any]) -> RideActivityAttributes.ContentState {
        var state = current
        if let value = payload["speed"] as? String { state.speed = value }
        if let value = payload["speedUnit"] as? String { state.speedUnit = value }
        if let value = payload["speedCompact"] as? String { state.speedCompact = value }
        if let value = payload["distance"] as? String { state.distance = value }
        if let value = payload["distanceUnit"] as? String { state.distanceUnit = value }
        if let value = payload["elapsed"] as? String { state.elapsed = value }
        if let value = payload["heartRate"] as? String { state.heartRate = value }
        if let value = payload["ascent"] as? String { state.ascent = value }
        if let value = payload["ascentUnit"] as? String { state.ascentUnit = value }
        if let value = payload["paused"] as? Bool { state.paused = value }
        if let value = payload["pauseLabel"] as? String { state.pauseLabel = value }
        if let value = payload["live"] as? Bool { state.live = value }
        if let value = payload["maneuver"] as? String { state.maneuver = value }
        if let value = payload["maneuverStreet"] as? String { state.maneuverStreet = value }
        if let value = payload["maneuverDistance"] as? String { state.maneuverDistance = value }
        if let value = payload["maneuverSymbol"] as? String { state.maneuverSymbol = value }
        if let value = payload["offRoute"] as? Bool { state.offRoute = value }
        if let value = payload["routeShape"] as? String { state.routeShape = value }
        if let value = payload["routeAspect"] as? Double { state.routeAspect = value }
        if let value = payload["routeProgress"] as? Double { state.routeProgress = value }
        if let value = payload["remainingDistance"] as? String { state.remainingDistance = value }
        if let value = payload["navigating"] as? Bool { state.navigating = value }
        return state
    }

    /// Po tylu sekundach bez aktualizacji karta jest oznaczona jako nieświeża,
    /// żeby rzut oka na ekran blokady nie podał prędkości sprzed kwadransa
    /// jako aktualnej.
    private static func staleDate() -> Date {
        Date().addingTimeInterval(120)
    }
}
#endif
