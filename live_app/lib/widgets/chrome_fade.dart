import 'package:flutter/material.dart';

import '../i18n/strings.dart';

import '../core/lr_theme.dart';

/// Wraps a piece of secondary ride UI so it can retire out of the way.
///
/// After a few seconds of no interaction the ride computer should stop looking
/// like an app: buttons go, the instrument stays. Three rules make that feel
/// right rather than annoying.
///
///  * Retiring is slower than returning. Chrome dissolves gently and snaps
///    back the moment a hand touches the screen.
///  * Hidden chrome stops accepting touches the instant it starts to fade, so
///    a tap can never land on a half-transparent FINISH button.
///  * [collapse] additionally gives the space back, which is how the map grows
///    when the control bar retires.
class ChromeFade extends StatelessWidget {
  const ChromeFade({
    super.key,
    required this.visible,
    required this.child,
    this.collapse = false,
    this.alignment = Alignment.topCenter,
  });

  final bool visible;
  final Widget child;

  /// Also animate the occupied space away, not just the opacity.
  final bool collapse;

  /// Which edge the collapse animates towards.
  final Alignment alignment;

  /// Returning is near-instant: the rider has already asked for it.
  static const Duration showDuration = Duration(milliseconds: 150);

  /// Retiring is unhurried, so nothing appears to flinch away.
  static const Duration hideDuration = Duration(milliseconds: 420);

  static Duration durationFor({required bool visible}) =>
      visible ? showDuration : hideDuration;

  static Curve curveFor({required bool visible}) =>
      visible ? Curves.easeOut : Curves.easeInOutCubic;

  @override
  Widget build(BuildContext context) {
    final duration = durationFor(visible: visible);
    final curve = curveFor(visible: visible);

    final faded = IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: duration,
        curve: curve,
        child: child,
      ),
    );

    if (!collapse) return faded;

    return ClipRect(
      child: AnimatedAlign(
        alignment: alignment,
        heightFactor: visible ? 1 : 0,
        duration: duration,
        curve: curve,
        child: faded,
      ),
    );
  }
}

/// The one-off "tap to bring the controls back" note.
///
/// It is shown the first time a ride goes quiet and never again, because the
/// gesture only has to be learned once.
class ChromeHint extends StatelessWidget {
  const ChromeHint({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: visible
          ? const Duration(milliseconds: 220)
          : const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: LR.ink.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          S.tapToShowControls,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
      ),
    ),
  );
}
