import 'package:flutter/material.dart';

import '../core/lr_theme.dart';
import '../i18n/strings.dart';

/// Blokada ekranu na czas jazdy.
///
/// Przykrywa cały ekran i połyka każde dotknięcie, więc krople deszczu ani
/// przypadkowe muśnięcie kolanem nic nie zrobią. Odblokowanie wymaga
/// świadomego gestu — przytrzymania, nie stuknięcia.
class ScreenLockOverlay extends StatefulWidget {
  const ScreenLockOverlay({
    super.key,
    required this.locked,
    required this.onUnlock,
    this.holdDuration = const Duration(milliseconds: 1200),
  });

  final bool locked;
  final VoidCallback onUnlock;
  final Duration holdDuration;

  @override
  State<ScreenLockOverlay> createState() => _ScreenLockOverlayState();
}

class _ScreenLockOverlayState extends State<ScreenLockOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hold =
      AnimationController(vsync: this, duration: widget.holdDuration)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            _hold.reset();
            widget.onUnlock();
          }
        });

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.locked) return const SizedBox.shrink();

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _hold.forward(),
        onTapUp: (_) => _hold.reverse(),
        onTapCancel: () => _hold.reverse(),
        onLongPressStart: (_) => _hold.forward(),
        onLongPressEnd: (_) => _hold.reverse(),
        child: Container(
          // Prawie przezroczysty: zawodnik ma wciąż widzieć swoje liczby,
          // tylko nie móc ich przypadkiem zmienić.
          color: LR.ink.withValues(alpha: 0.06),
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: AnimatedBuilder(
                animation: _hold,
                builder: (context, _) => Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  decoration: BoxDecoration(
                    color: LR.ink.withValues(alpha: 0.86),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: _hold.value > 0
                            ? CircularProgressIndicator(
                                value: _hold.value,
                                strokeWidth: 2,
                                color: Colors.white,
                              )
                            : const Icon(
                                Icons.lock_outline,
                                size: 18,
                                color: Colors.white,
                              ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        S.holdToUnlock,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
