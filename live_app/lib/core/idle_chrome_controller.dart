import 'dart:async';

import 'package:flutter/foundation.dart';

/// Decides when the ride computer stops being an app.
///
/// After [idleDelay] without a touch the secondary controls retire and the
/// screen becomes an instrument: map, route, next turn and data fields. Any
/// touch brings them straight back.
///
/// The rules that keep this from being irritating live here rather than in the
/// screen, so they can be tested without a device:
///
///  * chrome never retires while [canRetire] says the ride is not in a plain
///    recording state — paused, errored or mid-save keeps the controls up;
///  * [hold] pins the controls open for as long as a sheet or dialog is up,
///    and nests, so two overlapping holds cannot release each other early;
///  * the gesture hint is shown once and then never again.
class IdleChromeController extends ChangeNotifier {
  IdleChromeController({
    required this.canRetire,
    this.idleDelay = const Duration(seconds: 5),
    this.hintDuration = const Duration(milliseconds: 1900),
  });

  /// Whether the ride is in a state where the controls may retire at all.
  final bool Function() canRetire;

  final Duration idleDelay;
  final Duration hintDuration;

  bool _visible = true;
  bool _hintVisible = false;
  bool _hintUsed = false;
  int _holds = 0;
  Timer? _idleTimer;
  Timer? _hintTimer;
  bool _disposed = false;

  /// True while the secondary controls are on screen.
  bool get visible => _visible;

  /// True while the one-off "tap to show controls" note is up.
  bool get hintVisible => _hintVisible;

  /// True once the hint has been shown, which happens at most once.
  bool get hintUsed => _hintUsed;

  /// True while something is pinning the controls open.
  bool get isHeld => _holds > 0;

  /// Call on every touch. Brings the controls back and restarts the countdown.
  void wake() {
    _hintTimer?.cancel();
    final changed = !_visible || _hintVisible;
    _visible = true;
    _hintVisible = false;
    if (changed) notifyListeners();
    restart();
  }

  /// Restarts the countdown without changing what is currently on screen.
  /// Used when the ride's state changes, for example on resume.
  void restart() {
    if (_disposed) return;
    _idleTimer?.cancel();
    if (_holds > 0 || !canRetire()) return;
    _idleTimer = Timer(idleDelay, _retire);
  }

  /// Pins the controls open. Every [hold] must be matched by a [release].
  void hold() {
    _holds++;
    _idleTimer?.cancel();
    wake();
  }

  void release() {
    if (_holds > 0) _holds--;
    restart();
  }

  void _retire() {
    if (_disposed || _holds > 0 || !canRetire() || !_visible) return;
    _visible = false;
    if (!_hintUsed) {
      _hintUsed = true;
      _hintVisible = true;
      _hintTimer?.cancel();
      _hintTimer = Timer(hintDuration, () {
        if (_disposed || !_hintVisible) return;
        _hintVisible = false;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _idleTimer?.cancel();
    _hintTimer?.cancel();
    super.dispose();
  }
}
