import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../i18n/strings.dart';

import '../core/lr_theme.dart';

/// A live heart-rate trace.
///
/// Deliberately not a chart: no axes, no grid, no legend. It exists so a rider
/// can tell at a glance whether the strap is producing a steady signal or
/// dropping in and out.
class BpmTrace extends StatelessWidget {
  const BpmTrace({
    super.key,
    required this.samples,
    this.height = 64,
    this.color = LR.alert,
  });

  final List<int> samples;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: samples.length < 2
        ? Center(
            child: Text(
              S.waitingForSignal,
              style: LR.fieldLabel.copyWith(fontSize: 9.5),
            ),
          )
        : CustomPaint(
            size: Size.infinite,
            painter: _TracePainter(samples: samples, color: color),
          ),
  );
}

class _TracePainter extends CustomPainter {
  _TracePainter({required this.samples, required this.color});

  final List<int> samples;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    var low = samples.first.toDouble();
    var high = samples.first.toDouble();
    for (final sample in samples) {
      low = math.min(low, sample.toDouble());
      high = math.max(high, sample.toDouble());
    }
    // A flat trace should read as flat, not as noise magnified to fill the box.
    final range = math.max(high - low, 12.0);
    final mid = (high + low) / 2;
    final top = mid + range / 2;

    final step = size.width / (samples.length - 1);
    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final x = i * step;
      final y = ((top - samples[i]) / range) * (size.height - 8) + 4;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final area = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas
      ..drawPath(area, Paint()..color = color.withValues(alpha: 0.12))
      ..drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );

    // The most recent beat gets a dot so the trace reads as live.
    final lastX = (samples.length - 1) * step;
    final lastY = ((top - samples.last) / range) * (size.height - 8) + 4;
    canvas.drawCircle(Offset(lastX, lastY), 3.2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TracePainter oldDelegate) =>
      oldDelegate.samples.length != samples.length ||
      (samples.isNotEmpty &&
          oldDelegate.samples.isNotEmpty &&
          oldDelegate.samples.last != samples.last);
}

/// Four bars of signal strength, the way a phone shows reception.
class SignalBars extends StatelessWidget {
  const SignalBars({super.key, required this.bars, this.size = 14});

  final int bars;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 1; i <= 4; i++) ...[
          Expanded(
            child: Container(
              height: size * (0.3 + i * 0.175),
              color: i <= bars ? LR.ink : LR.line,
            ),
          ),
          if (i < 4) SizedBox(width: size * 0.09),
        ],
      ],
    ),
  );
}
