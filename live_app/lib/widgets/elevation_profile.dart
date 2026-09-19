import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/lr_theme.dart';

/// The elevation chart on a ride summary. Filled area, hairline axis, no grid
/// clutter — an instrument readout rather than a business chart.
class ElevationProfile extends StatelessWidget {
  const ElevationProfile({
    super.key,
    required this.samples,
    this.metric = true,
    this.height = 132,
  });

  final List<({double distance, double altitude})> samples;
  final bool metric;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (samples.length < 3) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text('No elevation data recorded', style: LR.body),
        ),
      );
    }

    var minAltitude = samples.first.altitude;
    var maxAltitude = samples.first.altitude;
    for (final sample in samples) {
      minAltitude = math.min(minAltitude, sample.altitude);
      maxAltitude = math.max(maxAltitude, sample.altitude);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: CustomPaint(
            painter: _ElevationPainter(
              samples: samples,
              minAltitude: minAltitude,
              maxAltitude: maxAltitude,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              '${Fmt.elevation(minAltitude, metric: metric)} '
              '${Fmt.elevationUnit(metric: metric)}',
              style: LR.fieldLabel,
            ),
            const Spacer(),
            Text(
              '${Fmt.elevation(maxAltitude, metric: metric)} '
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
    required this.minAltitude,
    required this.maxAltitude,
  });

  final List<({double distance, double altitude})> samples;
  final double minAltitude;
  final double maxAltitude;

  @override
  void paint(Canvas canvas, Size size) {
    final totalDistance = samples.last.distance - samples.first.distance;
    if (totalDistance <= 0) return;
    final range = math.max(maxAltitude - minAltitude, 10.0);

    Offset pointAt(({double distance, double altitude}) sample) {
      final x =
          (sample.distance - samples.first.distance) /
          totalDistance *
          size.width;
      final y =
          size.height -
          ((sample.altitude - minAltitude) / range) * (size.height - 10) -
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
