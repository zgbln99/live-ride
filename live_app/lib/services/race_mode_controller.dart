import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../data/settings_dao.dart';

/// Tryb wyścigu i blokada ekranu.
///
/// Tryb wyścigu robi dwie rzeczy naraz: chowa wszystko poza liczbami i
/// podbija jasność, żeby dało się je odczytać w pełnym słońcu. Blokada
/// ekranu jest osobno, bo przydaje się też w deszczu — krople na szybie
/// potrafią naciskać przyciski same.
class RaceModeController extends ChangeNotifier {
  RaceModeController({SettingsDao? settings, ScreenBrightness? brightness})
    : _settings = settings,
      _brightness = brightness ?? ScreenBrightness();

  static const String settingsKey = 'race_mode';

  /// Jasność w trybie wyścigu. Nie 1.0: pełna jasność zjada baterię szybciej,
  /// niż daje czytelności.
  static const double raceBrightness = 0.9;

  final SettingsDao? _settings;
  final ScreenBrightness _brightness;

  bool _raceMode = false;
  bool _screenLocked = false;
  bool _boostBrightness = true;
  double? _restoreBrightness;
  String? _lastError;

  bool get isRaceMode => _raceMode;
  bool get isScreenLocked => _screenLocked;
  bool get boostBrightness => _boostBrightness;

  /// Ostatni błąd sterowania jasnością — na niektórych urządzeniach system
  /// tego nie pozwala, i lepiej to powiedzieć niż udawać, że zadziałało.
  String? get lastError => _lastError;

  Future<void> restore() async {
    final stored = await _settings?.readJson(settingsKey);
    if (stored == null) return;
    _boostBrightness = stored['boost_brightness'] as bool? ?? true;
    notifyListeners();
  }

  Future<void> setBoostBrightness(bool value) async {
    _boostBrightness = value;
    notifyListeners();
    await _settings?.writeJson(settingsKey, {'boost_brightness': value});
    if (_raceMode) {
      value ? await _applyBrightness() : await _restore();
    }
  }

  Future<void> setRaceMode(bool value) async {
    if (_raceMode == value) return;
    _raceMode = value;
    notifyListeners();
    if (value) {
      if (_boostBrightness) await _applyBrightness();
    } else {
      _screenLocked = false;
      await _restore();
      notifyListeners();
    }
  }

  void lockScreen() {
    if (_screenLocked) return;
    _screenLocked = true;
    notifyListeners();
  }

  void unlockScreen() {
    if (!_screenLocked) return;
    _screenLocked = false;
    notifyListeners();
  }

  /// Wołane, gdy jazda się kończy — tryb wyścigu nie ma prawa przeżyć
  /// przejazdu i zostawić telefonu z podkręconą jasnością.
  Future<void> reset() async {
    _screenLocked = false;
    if (_raceMode) {
      _raceMode = false;
      await _restore();
    }
    notifyListeners();
  }

  Future<void> _applyBrightness() async {
    try {
      _restoreBrightness ??= await _brightness.application;
      await _brightness.setApplicationScreenBrightness(raceBrightness);
      _lastError = null;
    } on PlatformException catch (e) {
      _lastError = e.message;
    } on MissingPluginException {
      // Desktop i testy — nie ma czego ustawiać.
    }
    notifyListeners();
  }

  Future<void> _restore() async {
    final previous = _restoreBrightness;
    _restoreBrightness = null;
    if (previous == null) return;
    try {
      await _brightness.resetApplicationScreenBrightness();
    } on PlatformException catch (e) {
      _lastError = e.message;
    } on MissingPluginException {
      // Jak wyżej.
    }
  }

  @override
  void dispose() {
    unawaited(_restore());
    super.dispose();
  }
}
