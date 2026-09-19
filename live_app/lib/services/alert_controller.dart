import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../data/settings_dao.dart';
import '../models/ride_alert.dart';
import 'alert_engine.dart';

/// Trzyma bieżące powiadomienie i decyduje, jak mocno zawibrować.
///
/// Sam silnik nic nie wie o telefonie; kontroler dokłada wibrację, czas
/// pokazania i zapamiętane ustawienia.
class AlertController extends ChangeNotifier {
  AlertController({SettingsDao? settings, AlertEngine? engine, FlutterTts? tts})
    : _settings = settings,
      _engine = engine ?? AlertEngine(),
      _tts = tts;

  static const String settingsKey = 'ride_alerts';

  /// Jak długo powiadomienie zostaje na ekranie, gdy nikt go nie zamknie.
  static const Duration visibleFor = Duration(seconds: 8);

  final SettingsDao? _settings;
  final AlertEngine _engine;
  final FlutterTts? _tts;
  FlutterTts? _voice;
  bool _voiceReady = false;

  final List<RideAlert> _history = [];
  RideAlert? _current;
  Timer? _hideTimer;
  bool _hapticsEnabled = true;
  bool _speechEnabled = false;

  RideAlert? get current => _current;
  List<RideAlert> get history => List.unmodifiable(_history);
  AlertSettings get settings => _engine.settings;
  bool get hapticsEnabled => _hapticsEnabled;
  bool get speechEnabled => _speechEnabled;

  Future<void> restore() async {
    final stored = await _settings?.readJson(settingsKey);
    if (stored == null) return;
    try {
      _engine.settings = AlertSettings.fromJson(stored);
      _hapticsEnabled = stored['haptics'] as bool? ?? true;
      _speechEnabled = stored['speech'] as bool? ?? false;
    } catch (_) {
      _engine.settings = AlertSettings.defaults;
    }
    notifyListeners();
  }

  Future<void> updateSettings(AlertSettings settings) async {
    _engine.settings = settings;
    notifyListeners();
    await _settings?.writeJson(settingsKey, {
      ...settings.toJson(),
      'haptics': _hapticsEnabled,
      'speech': _speechEnabled,
    });
  }

  Future<void> setHaptics(bool enabled) async {
    _hapticsEnabled = enabled;
    await updateSettings(_engine.settings);
  }

  Future<void> setSpeech(bool enabled) async {
    _speechEnabled = enabled;
    await updateSettings(_engine.settings);
  }

  /// Podaje stan jazdy i pokazuje to, co silnik uzna za warte uwagi.
  void feed(AlertContext context) {
    final alerts = _engine.evaluate(context);
    if (alerts.isEmpty) return;

    // Gdy w jednej chwili wypadnie kilka, pokazujemy najpilniejsze; reszta
    // trafia do historii, żeby nie zginęła, ale nie zasypuje ekranu.
    alerts.sort((a, b) => b.severity.index.compareTo(a.severity.index));
    _history.addAll(alerts);
    if (_history.length > 50) {
      _history.removeRange(0, _history.length - 50);
    }
    show(alerts.first);
  }

  void show(RideAlert alert) {
    _current = alert;
    _hideTimer?.cancel();
    _hideTimer = Timer(visibleFor, dismiss);
    unawaited(_vibrate(alert.severity));
    unawaited(_speak(alert));
    notifyListeners();
  }

  void dismiss() {
    if (_current == null) return;
    _current = null;
    _hideTimer?.cancel();
    _hideTimer = null;
    notifyListeners();
  }

  void reset() {
    _engine.reset();
    _history.clear();
    dismiss();
  }

  /// Czyta powiadomienie na głos.
  ///
  /// Po polsku i krótko: zdanie dłuższe niż kilka słów przestaje być
  /// zrozumiałe w wietrze i pod hełmem.
  Future<void> _speak(RideAlert alert) async {
    if (!_speechEnabled) return;
    try {
      final voice = _voice ??= _tts ?? FlutterTts();
      if (!_voiceReady) {
        await voice.setLanguage('pl-PL');
        await voice.setSpeechRate(0.5);
        _voiceReady = true;
      }
      await voice.speak('${alert.headline}. ${alert.message}');
    } on PlatformException {
      // Brak silnika mowy na urządzeniu — reszta powiadomienia działa.
    } on MissingPluginException {
      _speechEnabled = false;
    }
  }

  Future<void> _vibrate(AlertSeverity severity) async {
    if (!_hapticsEnabled) return;
    try {
      switch (severity) {
        case AlertSeverity.info:
          await HapticFeedback.lightImpact();
        case AlertSeverity.warning:
          await HapticFeedback.mediumImpact();
        case AlertSeverity.critical:
          await HapticFeedback.heavyImpact();
          await Future<void>.delayed(const Duration(milliseconds: 140));
          await HapticFeedback.heavyImpact();
      }
    } on MissingPluginException {
      // Na desktopie i w testach wibracji po prostu nie ma.
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }
}
