import Flutter
import Foundation
import WatchConnectivity

/// Most między Apple Watch a Flutterem.
///
/// Zegarek nadaje tętno przez WatchConnectivity. Ta klasa jest jedynym
/// miejscem po stronie telefonu, które o tym wie: przyjmuje próbkę, sprawdza,
/// czy w ogóle jest próbką, i wpycha ją w kanał zdarzeń. Reszta aplikacji
/// widzi zwykły strumień liczb i nie musi wiedzieć, skąd przyszły.
///
/// Gdy projekt zbudowano bez targetu watchOS, most i tak istnieje i po prostu
/// odpowiada „brak zegarka". To lepsze niż brak kanału: Dart dostaje wtedy
/// jednoznaczną odpowiedź zamiast wyjątku o nieistniejącej wtyczce.
final class LiveRideWatchBridge: NSObject {
    private let channel: FlutterMethodChannel
    private var events: FlutterEventSink?
    private var streaming = false

    @discardableResult
    static func register(with messenger: FlutterBinaryMessenger) -> LiveRideWatchBridge {
        let bridge = LiveRideWatchBridge(messenger: messenger)
        return bridge
    }

    private init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "live_ride/watch", binaryMessenger: messenger)
        super.init()

        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
        FlutterEventChannel(
            name: "live_ride/watch/heart_rate",
            binaryMessenger: messenger
        ).setStreamHandler(self)

        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "state":
            result(state())
        case "start":
            send(command: "start")
            result(state())
        case "stop":
            send(command: "stop")
            streaming = false
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func state() -> [String: Any] {
        guard WCSession.isSupported() else {
            return ["paired": false, "installed": false, "streaming": false]
        }
        let session = WCSession.default
        return [
            "paired": session.isPaired,
            "installed": session.isWatchAppInstalled,
            "reachable": session.isReachable,
            "streaming": streaming,
        ]
    }

    private func send(command: String) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired else { return }
        if session.isReachable {
            session.sendMessage(["command": command], replyHandler: nil, errorHandler: nil)
        } else {
            // Zegarek poza zasięgiem podniesie to przy najbliższym
            // połączeniu. Kolejkowanie kilku poleceń nie ma sensu — liczy
            // się ostatnie.
            try? session.updateApplicationContext(["command": command])
        }
    }

    private func deliver(_ payload: [String: Any]) {
        if let value = payload["streaming"] as? Bool {
            streaming = value
        }
        guard
            let bpm = payload["bpm"] as? Int,
            (25...260).contains(bpm)
        else { return }
        let at = payload["at"] as? Int ?? Int(Date().timeIntervalSince1970 * 1000)
        DispatchQueue.main.async { [weak self] in
            self?.events?(["bpm": bpm, "at": at])
        }
    }
}

extension LiveRideWatchBridge: FlutterStreamHandler {
    func onListen(
        withArguments arguments: Any?,
        eventSink: @escaping FlutterEventSink
    ) -> FlutterError? {
        events = eventSink
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        events = nil
        return nil
    }
}

extension LiveRideWatchBridge: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Przełączenie zegarka wymaga ponownej aktywacji, inaczej most
        // milczy do końca życia procesu.
        WCSession.default.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        deliver(message)
    }

    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        deliver(applicationContext)
    }
}
