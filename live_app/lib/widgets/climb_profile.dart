import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../models/route/route_analysis.dart';

/// Profil wysokości trasy z zaznaczonymi podjazdami.
///
/// Ten sam rysunek obsługuje briefing (cała trasa) i ClimbPro (pojedynczy
/// podjazd z pozycją zawodnika), dlatego zakres da się przyciąć przez
/// [fromMeters] / [toMeters], a bieżące położenie podać w [positionMeters].
class ClimbProfileChart extends StatelessWidget {
  const ClimbProfileChart({
    super.key,
    required this.samples,
    this.climbs = const [],
    this.height = 150,
    this.metric = true,
    this.positionMeters,
    this.fromMeters,
    this.toMeters,
    this.highlight,
    this.showAxis = true,
  });

  final List<({double distance, double elevation})> samples;
  final List<Climb> climbs;
  final double height;
  final bool metric;

  /// Położenie zawodnika na trasie — rysowane jako pionowa linia.
  final double? positionMeters;

  final double? fromMeters;
  final double? toMeters;

  /// Podjazd rysowany mocniejszym kolorem (np. ten, na którym się jest).
  final Climb? highlight;

  final bool showAxis;

  @override
  Widget build(BuildContext context) {
    final visible = _visibleSamples();
    if (visible.length < 3) {
      return SizedBox(
        height: height,
        child: Center(child: Text(S.noElevationData, style: LR.body)),
      );
    }

    var minElevation = visible.first.elevation;
    var maxElevation = visible.first.elevation;
    for (final sample in visible) {
      minElevation = math.min(minElevation, sample.elevation);
      maxElevation = math.max(maxElevation, sample.elevation);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: CustomPaint(
            painter: _ClimbProfilePainter(
              samples: visible,
              climbs: climbs,
              minElevation: minElevation,
              maxElevation: maxElevation,
              positionMeters: positionMeters,
              highlight: highlight,
            ),
          ),
        ),
        if (showAxis) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${Fmt.distance(visible.first.distance, metric: metric)} '
                '${Fmt.distanceUnit(metric: metric)}',
                style: LR.body.copyWith(fontSize: 11),
              ),
              Text(
                '${Fmt.elevation(minElevation, metric: metric)}–'
                '${Fmt.elevation(maxElevation, metric: metric)} '
                '${Fmt.elevationUnit(metric: metric)}',
                style: LR.body.copyWith(fontSize: 11),
              ),
              Text(
                '${Fmt.distance(visible.last.distance, metric: metric)} '
                '${Fmt.distanceUnit(metric: metric)}',
                style: LR.body.copyWith(fontSize: 11),
              ),
            ],
          ),
        ],
      ],
    );
  }

  List<({double distance, double elevation})> _visibleSamples() {
    final from = fromMeters;
    final to = toMeters;
    if (from == null && to == null) return samples;
    return samples
        .where(
          (sample) =>
              (from == null || sample.distance >= from) &&
              (to == null || sample.distance <= to),
        )
        .toList();
  }
}

class _ClimbProfilePainter extends CustomPainter {
  _ClimbProfilePainter({
    required this.samples,
    required this.climbs,
    required this.minElevation,
    required this.maxElevation,
    required this.positionMeters,
    required this.highlight,
  });

  final List<({double distance, double elevation})> samples;
  final List<Climb> climbs;
  final double minElevation;
  final double maxElevation;
  final double? positionMeters;
  final Climb? highlight;

  @override
  void paint(Canvas canvas, Size size) {
    final startDistance = samples.first.distance;
    final span = math.max(samples.last.distance - startDistance, 1.0);
    final range = math.max(maxElevation - minElevation, 10.0);

    double dx(double distance) =>
        (distance - startDistance) / span * size.width;
    double dy(double elevation) =>
        size.height -
        (elevation - minElevation) / range * (size.height - 10) -
        5;

    // Cieniowanie podjazdów — im ostrzejszy, tym mocniejszy kolor.
    for (final climb in climbs) {
      final left = dx(climb.startDistanceMeters).clamp(0.0, size.width);
      final right = dx(climb.endDistanceMeters).clamp(0.0, size.width);
      if (right <= left) continue;
      final intensity = (climb.averageGradientPercent / 12).clamp(0.12, 0.55);
      canvas.drawRect(
        Rect.fromLTRB(left, 0, right, size.height),
        Paint()
          ..color = (identical(climb, highlight) ? LR.alert : LR.accentDeep)
              .withValues(alpha: intensity.toDouble() * 0.45),
      );
    }

    final path = Path()
      ..moveTo(dx(samples.first.distance), dy(samples.first.elevation));
    for (final sample in samples.skip(1)) {
      path.lineTo(dx(sample.distance), dy(sample.elevation));
    }

    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x3300BFD8), Color(0x0A00BFD8)],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = LR.accentDeep,
    );

    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      Paint()
        ..color = LR.line
        ..strokeWidth = 1,
    );

    final position = positionMeters;
    if (position != null &&
        position >= startDistance &&
        position <= samples.last.distance) {
      final x = dx(position);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = LR.alert
          ..strokeWidth = 2,
      );
      canvas.drawCircle(
        Offset(x, dy(_elevationAt(position))),
        4,
        Paint()..color = LR.alert,
      );
    }
  }

  double _elevationAt(double distance) {
    for (var i = 1; i < samples.length; i++) {
      if (samples[i].distance >= distance) {
        final previous = samples[i - 1];
        final current = samples[i];
        final span = current.distance - previous.distance;
        if (span <= 0) return current.elevation;
        final t = (distance - previous.distance) / span;
        return previous.elevation +
            (current.elevation - previous.elevation) * t;
      }
    }
    return samples.last.elevation;
  }

  @override
  bool shouldRepaint(_ClimbProfilePainter oldDelegate) =>
      oldDelegate.samples != samples ||
      oldDelegate.climbs != climbs ||
      oldDelegate.positionMeters != positionMeters ||
      oldDelegate.highlight != highlight;
}
