import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/geo.dart';
import '../data/settings_dao.dart';
import '../i18n/strings.dart';
import '../models/emergency.dart';
import 'crash_detector.dart';

/// Stan alarmu.
enum SosState {
  /// Nic się nie dzieje.
  idle,

  /// Odliczanie — zawodnik może anulować.
  countdown,

  /// Odliczanie doszło do zera; czas wysłać wiadomość.
  armed,
}

/// Wykrywanie upadku, ręczne SOS i kontakty alarmowe.
///
/// Serwis nie wysyła niczego sam z siebie po cichu: alarm zawsze przechodzi
/// przez odliczanie, które da się anulować, a wiadomość wychodzi przez
/// systemową aplikację SMS, gdzie zawodnik widzi treść przed wysłaniem.
/// Automatyczna wysyłka SMS bez udziału użytkownika nie jest możliwa na iOS
/// i udawanie, że jest, byłoby kłamstwem o działającej funkcji.
class SafetyService extends ChangeNotifier {
  SafetyService({
    SettingsDao? settings,
    CrashDetector? detector,
    Stream<UserAccelerometerEvent>? accelerometer,
  }) : _settings = settings,
       _detector = detector ?? CrashDetector(),
       _accelerometerOverride = accelerometer;

  static const String settingsKey = 'safety';

  final SettingsDao? _settings;
  final CrashDetector _detector;
  final Stream<UserAccelerometerEvent>? _accelerometerOverride;

  StreamSubscription<UserAccelerometerEvent>? _accelerometerSub;
  Timer? _countdown;

  SafetySettings _config = const SafetySettings();
  SosState _state = SosState.idle;
  int _secondsLeft = 0;
  bool _automatic = false;
  GeoPoint? _lastPosition;
  String? _liveUrl;

  SafetySettings get settings => _config;
  SosState get state => _state;
  int get secondsLeft => _secondsLeft;

  /// Czy odliczanie zaczęło się samo, czy zawodnik nacisnął SOS.
  bool get isAutomatic => _automatic;

  bool get isAlarming => _state != SosState.idle;

  Future<void> restore() async {
    final stored = await _settings?.readJson(settingsKey);
    if (stored == null) return;
    try {
      _config = SafetySettings.fromJson(stored);
      _detector.sensitivity = _config.sensitivity;
    } catch (_) {
      _config = const SafetySettings();
    }
    notifyListeners();
  }

  Future<void> update(SafetySettings settings) async {
    _config = settings;
    _detector.sensitivity = settings.sensitivity;
    notifyListeners();
    await _settings?.writeJson(settingsKey, settings.toJson());
  }

  /// Startuje razem z przejazdem.
  void startWatching() {
    _detector.reset();
    if (!_config.isUsable) return;
    _accelerometerSub?.cancel();
    final stream =
        _accelerometerOverride ??
        userAccelerometerEventStream(
          samplingPeriod: const Duration(milliseconds: 100),
        );
    _accelerometerSub = stream.listen(
      _onAcceleration,
      onError: (_) {
        // Brak akcelerometru (desktop, emulator) nie może wywalić jazdy.
      },
    );
  }

  void stopWatching() {
    _accelerometerSub?.cancel();
    _accelerometerSub = null;
    _detector.reset();
    cancelAlarm();
  }

  void _onAcceleration(UserAccelerometerEvent event) {
    // Strumień podaje metry na sekundę do kwadratu, bez grawitacji.
    final magnitude =
        math.sqrt(event.x * event.x + event.y * event.y + event.z * event.z) /
        9.80665;
    _detector.feedAcceleration(magnitude, DateTime.now());
  }

  /// Podawane przez rejestrator przy każdej pozycji.
  void updateRide({
    required double speedKmh,
    GeoPoint? position,
    String? liveUrl,
  }) {
    _lastPosition = position ?? _lastPosition;
    _liveUrl = liveUrl ?? _liveUrl;
    if (!_config.isUsable || _state != SosState.idle) return;
    if (_detector.feedSpeed(speedKmh, DateTime.now())) {
      _startCountdown(automatic: true);
    }
  }

  /// Ręczne SOS — ten sam tor, to samo odliczanie.
  void triggerManual() => _startCountdown(automatic: false);

  void _startCountdown({required bool automatic}) {
    if (_state != SosState.idle) return;
    _automatic = automatic;
    _state = SosState.countdown;
    _secondsLeft = math.max(5, _config.countdownSeconds);
    notifyListeners();

    _countdown?.cancel();
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      _secondsLeft--;
      if (_secondsLeft <= 0) {
        timer.cancel();
        _state = SosState.armed;
      }
      notifyListeners();
      if (_state == SosState.countdown) {
        unawaited(_pulse());
      }
    });
  }

  void cancelAlarm() {
    _countdown?.cancel();
    _countdown = null;
    if (_state == SosState.idle) return;
    _state = SosState.idle;
    _secondsLeft = 0;
    _automatic = false;
    _detector.reset();
    notifyListeners();
  }

  /// Treść wiadomości alarmowej.
  ///
  /// Współrzędne idą jako link do mapy, bo to jedyna forma, którą każdy
  /// odbiorca otworzy bez zastanowienia.
  @visibleForTesting
  String composeMessage({GeoPoint? position, String? liveUrl}) {
    final point = position ?? _lastPosition;
    final live = liveUrl ?? _liveUrl;
    return [
      _automatic ? S.sosCrashMessage : S.sosManualMessage,
      if (point != null)
        'https://www.google.com/maps/search/?api=1&query='
            '${point.lat.toStringAsFixed(5)},${point.lon.toStringAsFixed(5)}',
      if (live != null && _config.shareLiveLink) live,
    ].join('\n');
  }

  /// Otwiera aplikację SMS z gotową treścią do wszystkich kontaktów.
  ///
  /// Zwraca false, gdy nie ma do kogo albo system odmówił — wtedy ekran
  /// pokazuje numery, żeby dało się zadzwonić ręcznie.
  Future<bool> sendAlert() async {
    final contacts = _config.crashContacts;
    if (contacts.isEmpty) return false;
    final recipients = contacts.map((contact) => contact.phone).join(',');
    final uri = Uri(
      scheme: 'sms',
      path: recipients,
      queryParameters: {'body': composeMessage()},
    );
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> callContact(EmergencyContact contact) async {
    final uri = Uri(scheme: 'tel', path: contact.phone);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on PlatformException {
      // Brak aplikacji telefonu — ekran i tak pokazuje numer.
    } on MissingPluginException {
      // Jak wyżej.
    }
  }

  Future<void> _pulse() async {
    try {
      await HapticFeedback.heavyImpact();
    } on MissingPluginException {
      // Desktop i testy.
    }
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _accelerometerSub?.cancel();
    super.dispose();
  }
}
