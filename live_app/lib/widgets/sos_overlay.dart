import 'package:flutter/material.dart';

import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../services/safety_service.dart';

/// Odliczanie alarmu na całym ekranie.
///
/// Wielki przycisk anulowania jest pierwszy i największy, bo w dziewięciu
/// przypadkach na dziesięć zawodnikowi nic nie jest, a trafienie w mały
/// przycisk w rękawiczkach, leżąc w rowie, nie jest realistyczne.
class SosOverlay extends StatelessWidget {
  const SosOverlay({super.key, required this.safety, required this.onSend});

  final SafetyService safety;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    if (!safety.isAlarming) return const SizedBox.shrink();
    final armed = safety.state == SosState.armed;

    return Positioned.fill(
      child: Material(
        color: LR.alert.withValues(alpha: 0.96),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.report_problem_outlined,
                  color: Colors.white,
                  size: 54,
                ),
                const SizedBox(height: 18),
                Text(
                  safety.isAutomatic ? S.sosCrashTitle : S.sosManualTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  armed ? S.smsDisclaimer : S.sosCountdown(safety.secondsLeft),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  height: 78,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: LR.alert,
                      textStyle: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                    onPressed: safety.cancelAlarm,
                    child: Text(S.sosCancel),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 56,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white, width: 1.5),
                    ),
                    onPressed: () => onSend(),
                    child: Text(S.sosSendNow),
                  ),
                ),
                if (armed) ...[
                  const SizedBox(height: 18),
                  for (final contact in safety.settings.crashContacts)
                    TextButton.icon(
                      icon: const Icon(Icons.call, color: Colors.white),
                      label: Text(
                        '${S.call} ${contact.name} · ${contact.phone}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      onPressed: () => safety.callContact(contact),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
