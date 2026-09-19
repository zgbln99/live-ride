import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import '../core/geo.dart';
import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../services/app_services.dart';
import '../widgets/lr_common.dart';

/// Mapa cieplna wszystkich przejazdów.
///
/// Rysowana z przerzedzonych punktów z bazy: heatmapa z dwustu tysięcy
/// punktów wygląda tak samo jak z dwudziestu tysięcy, a rysuje się dziesięć
/// razy dłużej.
class HeatmapScreen extends StatefulWidget {
  const HeatmapScreen({super.key});

  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen> {
  List<GeoPoint> _points = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final points = await AppServices.of(context).rides.dao.heatmapPoints();
    if (!mounted) return;
    setState(() {
      _points = points;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(S.heatmap)),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _points.length < 10
        ? LrEmptyState(
            icon: Icons.map_outlined,
            title: S.heatmapEmpty,
            message: S.heatmapEmptyMessage,
          )
        : Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: CustomPaint(
                    painter: _HeatmapPainter(points: _points),
                    size: Size.infinite,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Text(
                  S.heatmapPointCount(_points.length),
                  style: LR.body.copyWith(fontSize: 12.5),
                ),
              ),
            ],
          ),
  );
}

class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter({required this.points});

  final List<GeoPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = GeoBounds.of(points);
    if (bounds == null) return;

    final latSpan = (bounds.maxLat - bounds.minLat).abs();
    final lonSpan = (bounds.maxLon - bounds.minLon).abs();
    if (latSpan <= 0 && lonSpan <= 0) return;

    // Skala wspólna dla obu osi, żeby kraj nie wyszedł spłaszczony.
    final scale = latSpan <= 0
        ? size.width / lonSpan
        : lonSpan <= 0
        ? size.height / latSpan
        : (size.width / lonSpan).clamp(0.0, size.height / latSpan);
    final offsetX = (size.width - lonSpan * scale) / 2;
    final offsetY = (size.height - latSpan * scale) / 2;

    final paint = Paint()
      ..color = LR.accentDeep.withValues(alpha: 0.28)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    final offsets = <Offset>[
      for (final point in points)
        Offset(
          offsetX + (point.lon - bounds.minLon) * scale,
          offsetY + (bounds.maxLat - point.lat) * scale,
        ),
    ];

    // Punkty, nie linie: kolejne próbki pochodzą z różnych przejazdów i
    // łączenie ich odcinkami narysowałoby trasy, których nikt nie przejechał.
    canvas.drawPoints(PointMode.points, offsets, paint);
  }

  @override
  bool shouldRepaint(_HeatmapPainter oldDelegate) =>
      oldDelegate.points != points;
}
