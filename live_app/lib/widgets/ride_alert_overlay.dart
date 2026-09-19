import 'package:flutter/material.dart';

import '../core/lr_theme.dart';
import '../models/ride_alert.dart';

/// Pasek powiadomienia nad mapą.
///
/// Wjeżdża od góry, sam znika i da się go zamknąć jednym dotknięciem.
/// Nigdy nie zasłania pól danych ani przycisków sterowania: w czasie jazdy
/// nic nie ma prawa zabrać zawodnikowi dostępu do pauzy.
class RideAlertOverlay extends StatelessWidget {
  const RideAlertOverlay({
    super.key,
    required this.alert,
    required this.onDismiss,
  });

  final RideAlert? alert;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final current = alert;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, animation) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.4),
          end: Offset.zero,
        ).animate(animation),
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: current == null
          ? const SizedBox.shrink(key: ValueKey('none'))
          : _AlertCard(
              key: ValueKey('${current.kind}-${current.at}'),
              alert: current,
              onDismiss: onDismiss,
            ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({super.key, required this.alert, required this.onDismiss});

  final RideAlert alert;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (alert.severity) {
      AlertSeverity.info => (LR.accentDeep, Icons.info_outline),
      AlertSeverity.warning => (
        const Color(0xFFE07A1F),
        Icons.warning_amber_rounded,
      ),
      AlertSeverity.critical => (LR.alert, Icons.error_outline),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Material(
        color: LR.surface,
        elevation: 4,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onDismiss,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color, width: 1.5),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alert.headline.toUpperCase(),
                        style: LR.fieldLabel.copyWith(color: color),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        alert.message,
                        style: LR.fieldValue(15),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.close, size: 16, color: LR.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
