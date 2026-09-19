import 'package:flutter/material.dart';

import '../core/lr_theme.dart';
import '../i18n/strings.dart';

/// Pasek, który mówi, dlaczego licznik stoi.
///
/// Dwa rodzaje pauzy wyglądają inaczej, bo wymagają czego innego: postój
/// wykryty przez licznik kończy się sam, gdy rower ruszy, a pauzę wciśniętą
/// palcem trzeba zdjąć palcem. Gdyby obie wyglądały tak samo, rowerzysta
/// czekałby, aż licznik sam wystartuje — a ten czekałby na niego.
///
/// Pasek, nie okno: zasłonięcie mapy komunikatem w środku jazdy jest gorsze
/// niż sam zatrzymany czas.
class PauseBanner extends StatelessWidget {
  const PauseBanner({
    super.key,
    required this.automatic,
    required this.onResume,
  });

  /// Czy pauzę włączył detektor postoju (a nie rowerzysta).
  final bool automatic;

  /// Wywoływane przyciskiem WZNÓW. Przy pauzie automatycznej przycisku nie
  /// ma — ona kończy się ruchem roweru.
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final color = automatic ? LR.inkSoft : LR.accentDeep;
    return Material(
      color: LR.surface,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          border: const Border(bottom: BorderSide(color: LR.line)),
          color: automatic ? LR.surface : LR.accent.withValues(alpha: 0.18),
        ),
        child: Row(
          children: [
            Icon(
              automatic ? Icons.pause_circle_outline : Icons.pause_circle,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    automatic ? S.autoPauseBannerTitle : S.manualPauseTitle,
                    style: LR.fieldLabel.copyWith(fontSize: 11, color: color),
                  ),
                  if (automatic)
                    Text(
                      S.autoPauseBannerHint,
                      style: LR.body.copyWith(fontSize: 11),
                    ),
                ],
              ),
            ),
            if (!automatic)
              TextButton(
                onPressed: onResume,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: LR.ink,
                ),
                child: Text(S.resume),
              ),
          ],
        ),
      ),
    );
  }
}
