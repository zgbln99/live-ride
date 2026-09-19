import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/geo.dart';
import '../core/lr_theme.dart';

/// A tiny vector sketch of a route or recorded track, used on list cards.
///
/// It is intentionally not a map: no tiles to fetch, no network, no jank while
/// scrolling a long history.
class TrackPreview extends StatelessWidget {
  const TrackPreview({
    super.key,
    required this.points,
    this.color = LR.accentDeep,
    this.strokeWidth = 2.2,
    this.showEndpoints = true,
    this.background = LR.panel,
  });

  final List<GeoPoint> points;
  final Color color;
  final double strokeWidth;
  final bool showEndpoints;
  final Color background;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Center(
          child: Icon(Icons.route_outlined, size: 18, color: LR.lineStrong),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: CustomPaint(
          painter: _TrackPainter(
            points: points,
            color: color,
            strokeWidth: strokeWidth,
            showEndpoints: showEndpoints,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.points,
    required this.color,
    required this.strokeWidth,
    required this.showEndpoints,
  });

  final List<GeoPoint> points;
  final Color color;
  final double strokeWidth;
  final bool showEndpoints;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = GeoBounds.of(points);
    if (bounds == null) return;

    const padding = 7.0;
    final width = size.width - padding * 2;
    final height = size.height - padding * 2;
    if (width <= 0 || height <= 0) return;

    final spanLat = (bounds.maxLat - bounds.minLat).abs();
    // Longitude degrees shrink away from the equator; correcting keeps the
    // sketch in proportion instead of stretching east-west.
    final latCorrection = math
        .cos(bounds.center.lat * math.pi / 180)
        .abs()
        .clamp(0.05, 1.0);
    final spanLon = (bounds.maxLon - bounds.minLon).abs() * latCorrection;
    final span = math.max(math.max(spanLat, spanLon), 1e-7);

    final scale = math.min(width, height) / span;
    final drawWidth = spanLon * scale;
    final drawHeight = spanLat * scale;
    final offsetX = (size.width - drawWidth) / 2;
    final offsetY = (size.height - drawHeight) / 2;

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final x = offsetX + (point.lon - bounds.minLon) * latCorrection * scale;
      final y = size.height - offsetY - (point.lat - bounds.minLat) * scale;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas
      ..drawPath(
        path,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth + 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      )
      ..drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );

    if (!showEndpoints) return;
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final start = metrics.first.getTangentForOffset(0)?.position;
    final end = metrics.last.getTangentForOffset(metrics.last.length)?.position;
    if (start != null) {
      canvas.drawCircle(start, strokeWidth + 1.4, Paint()..color = LR.go);
    }
    if (end != null) {
      canvas.drawCircle(end, strokeWidth + 1.4, Paint()..color = LR.alert);
    }
  }

  @override
  bool shouldRepaint(_TrackPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}
