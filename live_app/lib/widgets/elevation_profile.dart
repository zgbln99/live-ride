import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/lr_theme.dart';
import '../i18n/strings.dart';

/// The elevation chart on a ride summary. Filled area, hairline axis, no grid
/// clutter — an instrument readout rather than a business chart.
class ElevationProfile extends StatelessWidget {
  const ElevationProfile({
    super.key,
    required this.samples,
    this.metric = true,
    this.height = 132,
  });

  final List<({double distance, double elevation})> samples;
  final bool metric;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (samples.length < 3) {
      return SizedBox(
        height: height,
        child: Center(child: Text(S.noElevationData, style: LR.body)),
      );
    }

    var minElevation = samples.first.elevation;
    var maxElevation = samples.first.elevation;
    for (final sample in samples) {
      minElevation = math.min(minElevation, sample.elevation);
      maxElevation = math.max(maxElevation, sample.elevation);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: CustomPaint(
            painter: _ElevationPainter(
              samples: samples,
              minElevation: minElevation,
              maxElevation: maxElevation,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              '${Fmt.elevation(minElevation, metric: metric)} '
              '${Fmt.elevationUnit(metric: metric)}',
              style: LR.fieldLabel,
            ),
            const Spacer(),
            Text(
              '${Fmt.elevation(maxElevation, metric: metric)} '
              '${Fmt.elevationUnit(metric: metric)}',
              style: LR.fieldLabel,
            ),
          ],
        ),
      ],
    );
  }
}

class _ElevationPainter extends CustomPainter {
  _ElevationPainter({
    required this.samples,
    required this.minElevation,
    required this.maxElevation,
  });

  final List<({double distance, double elevation})> samples;
  final double minElevation;
  final double maxElevation;

  @override
  void paint(Canvas canvas, Size size) {
    final totalDistance = samples.last.distance - samples.first.distance;
    if (totalDistance <= 0) return;
    final range = math.max(maxElevation - minElevation, 10.0);

    Offset pointAt(({double distance, double elevation}) sample) {
      final x =
          (sample.distance - samples.first.distance) /
          totalDistance *
          size.width;
      final y =
          size.height -
          ((sample.elevation - minElevation) / range) * (size.height - 10) -
          4;
      return Offset(x, y);
    }

    final line = Path()..moveTo(0, pointAt(samples.first).dy);
    for (final sample in samples) {
      final point = pointAt(sample);
      line.lineTo(point.dx, point.dy);
    }

    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas
      ..drawPath(area, Paint()..color = LR.accent.withValues(alpha: 0.16))
      ..drawPath(
        line,
        Paint()
          ..color = LR.accentDeep
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      )
      ..drawLine(
        Offset(0, size.height),
        Offset(size.width, size.height),
        Paint()
          ..color = LR.line
          ..strokeWidth = 1,
      );
  }

  @override
  bool shouldRepaint(_ElevationPainter oldDelegate) =>
      oldDelegate.samples != samples;
}
