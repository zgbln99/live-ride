import 'package:flutter/material.dart';

import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../services/ride_intelligence.dart';

/// Panel Ride Intelligence na ekranie jazdy.
///
/// Ma wyglądać jak przyrząd, a nie jak asystent. Żadnej rozmowy, żadnych
/// zdań o tym, jak świetnie idzie — dwie, najwyżej trzy rzeczy, których nie
/// da się odczytać z samych pól danych: że za sześć kilometrów zacznie się
/// odcinek pod wiatr, że ETA właśnie się przesunęła, że został jeden podjazd.
///
/// Pusty panel jest poprawnym stanem. Jazda, w której nie dzieje się nic
/// wartego słowa, to dobra jazda — wtedy karta po prostu znika.
class IntelligenceCard extends StatelessWidget {
  const IntelligenceCard({
    super.key,
    required this.insights,
    required this.eta,
    this.limit = 3,
    this.onTap,
  });

  final List<RideInsight> insights;
  final EtaEstimate eta;

  /// Ile pozycji pokazujemy bez rozwijania.
  final int limit;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shown = insights.take(limit).toList();
    final etaLine = _etaLine();
    if (shown.isEmpty && etaLine == null) return const SizedBox.shrink();

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
        decoration: BoxDecoration(
          color: LR.surface,
          border: Border.all(color: LR.line),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(S.rideIntelligence, style: LR.fieldLabel),
            const SizedBox(height: 8),
            if (etaLine != null) _line('ETA', etaLine, LR.ink),
            for (final insight in shown)
              _line(
                insight.title,
                insight.body,
                insight.priority == InsightPriority.urgent ? LR.alert : LR.ink,
              ),
          ],
        ),
      ),
    );
  }

  /// ETA albo szczere „jeszcze liczę".
  ///
  /// „14:31" po trzech minutach jazdy to liczba wyssana z palca. Przedział
  /// dokładamy dopiero wtedy, gdy mamy z czego go policzyć.
  String? _etaLine() {
    if (eta.confidence == InsightConfidence.calibrating) {
      return eta.at == null ? S.etaCalibrating : null;
    }
    final at = eta.at;
    if (at == null) return null;
    final clock =
        '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
    final spread = eta.spread;
    return spread == null ? clock : '$clock ±${spread.inMinutes} min';
  }

  Widget _line(String title, String body, Color colour) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: LR.fieldLabel.copyWith(fontSize: 9.5, color: LR.muted),
        ),
        Text(
          body,
          style: LR.body.copyWith(fontSize: 13, color: colour, height: 1.3),
        ),
      ],
    ),
  );
}
