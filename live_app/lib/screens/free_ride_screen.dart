import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/ride_record.dart';
import '../services/heart_rate_service.dart';
import '../services/ride_storage_service.dart';

class FreeRideScreen extends StatefulWidget {
  const FreeRideScreen({
    super.key,
    required this.heartRate,
    required this.storage,
  });

  final HeartRateService heartRate;
  final RideStorageService storage;

  @override
  State<FreeRideScreen> createState() => _FreeRideScreenState();
}

class _FreeRideScreenState extends State<FreeRideScreen> {
  final List<RecordedRidePoint> _points = [];
  StreamSubscription<Position>? _positionSub;
  Timer? _timer;
  DateTime? _startedAt;
  Position? _lastAcceptedPosition;
  int _elapsedSeconds = 0;
  double _distanceMeters = 0;
  double _elevationGain = 0;
  double _speedKmh = 0;
  bool _started = false;
  bool _paused = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('Włącz usługi lokalizacji.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('Live Ride nie ma dostępu do lokalizacji.');
      }

      _startedAt = DateTime.now();
      _started = true;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _paused || !_started) return;
        setState(() => _elapsedSeconds++);
      });

      final current = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
        ),
      );
      _acceptPosition(current);

      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 3,
        ),
      ).listen(_acceptPosition, onError: (Object error) {
        if (mounted) setState(() => _error = error.toString());
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _acceptPosition(Position position) {
    if (!_started || _paused) return;

    final previous = _lastAcceptedPosition;
    if (previous != null) {
      final step = Geolocator.distanceBetween(
        previous.latitude,
        previous.longitude,
        position.latitude,
        position.longitude,
      );
      if (step.isFinite && step >= 0 && step < 250) {
        _distanceMeters += step;
      }

      final elevationDelta = position.altitude - previous.altitude;
      if (elevationDelta > 1 && elevationDelta < 30) {
        _elevationGain += elevationDelta;
      }
    }

    _lastAcceptedPosition = position;
    _speedKmh = position.speed.isFinite && position.speed > 0
        ? position.speed * 3.6
        : 0;

    _points.add(
      RecordedRidePoint(
        lat: position.latitude,
        lon: position.longitude,
        altitude: position.altitude,
        speed: position.speed.isFinite ? position.speed : 0,
        recordedAt: DateTime.now(),
        heartRate: widget.heartRate.latestBpm,
      ),
    );

    if (mounted) setState(() {});
  }

  void _togglePause() {
    setState(() {
      _paused = !_paused;
      _lastAcceptedPosition = null;
      if (_paused) _speedKmh = 0;
    });
  }

  Future<void> _finish() async {
    if (_saving) return;
    final shouldSave = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Zakończyć jazdę?'),
            content: Text(
              '${(_distanceMeters / 1000).toStringAsFixed(2)} km • ${_formatTime(_elapsedSeconds)}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Jedź dalej'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Zapisz'),
              ),
            ],
          ),
        ) ??
        false;
    if (!shouldSave || !mounted) return;

    setState(() => _saving = true);
    _started = false;
    _timer?.cancel();
    await _positionSub?.cancel();

    final now = DateTime.now();
    final started = _startedAt ?? now;
    final ride = RecordedRide(
      id: '${started.millisecondsSinceEpoch}',
      name: 'Jazda ${_two(started.day)}.${_two(started.month)} ${_two(started.hour)}:${_two(started.minute)}',
      startedAt: started,
      endedAt: now,
      movingSeconds: _elapsedSeconds,
      distanceMeters: _distanceMeters,
      elevationGainMeters: _elevationGain,
      points: List.unmodifiable(_points),
    );
    await widget.storage.save(ride);

    if (!mounted) return;
    Navigator.of(context).pop(ride);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positionSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final avg = _elapsedSeconds <= 0
        ? 0.0
        : (_distanceMeters / _elapsedSeconds) * 3.6;

    return PopScope(
      canPop: !_started,
      child: Scaffold(
        backgroundColor: const Color(0xFF071018),
        appBar: AppBar(
          backgroundColor: const Color(0xFF071018),
          foregroundColor: Colors.white,
          title: const Text('LIVE RIDE'),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              onPressed: _saving ? null : _finish,
              icon: const Icon(Icons.stop_circle_outlined),
              tooltip: 'Zakończ i zapisz',
            ),
          ],
        ),
        body: SafeArea(
          child: _error != null
              ? _errorView()
              : Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          _statusChip(),
                          const Spacer(),
                          if (widget.heartRate.latestBpm != null)
                            _smallMetric(
                              Icons.favorite,
                              '${widget.heartRate.latestBpm} bpm',
                            ),
                          const SizedBox(width: 8),
                          _smallMetric(Icons.gps_fixed, '${_points.length} pkt'),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        _speedKmh.toStringAsFixed(1),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 92,
                          height: .9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -5,
                        ),
                      ),
                      const Text(
                        'km/h',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF8D9AA6),
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Expanded(
                            child: _bigMetric(
                              'DYSTANS',
                              (_distanceMeters / 1000).toStringAsFixed(2),
                              'km',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _bigMetric(
                              'CZAS',
                              _formatTime(_elapsedSeconds),
                              '',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _bigMetric(
                              'ŚREDNIA',
                              avg.toStringAsFixed(1),
                              'km/h',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _bigMetric(
                              'W GÓRĘ',
                              _elevationGain.round().toString(),
                              'm',
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: _saving ? null : _togglePause,
                              icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                              label: Text(_paused ? 'Wznów' : 'Pauza'),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(58),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _saving ? null : _finish,
                              icon: const Icon(Icons.stop),
                              label: Text(_saving ? 'Zapisuję…' : 'Zakończ'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFFF4D4D),
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(58),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_off, color: Colors.white, size: 54),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Wróć'),
              ),
            ],
          ),
        ),
      );

  Widget _statusChip() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: _paused ? const Color(0xFF2A333B) : const Color(0xFF143A2B),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _paused ? Icons.pause : Icons.circle,
              size: 12,
              color: _paused ? Colors.orangeAccent : const Color(0xFF5BFFAE),
            ),
            const SizedBox(width: 7),
            Text(
              _paused ? 'PAUZA' : 'NAGRYWANIE',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );

  Widget _smallMetric(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF111C24),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 5),
            Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ],
        ),
      );

  Widget _bigMetric(String label, String value, String unit) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF111C24),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF21313D)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF8D9AA6),
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: value,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (unit.isNotEmpty)
                      TextSpan(
                        text: ' $unit',
                        style: const TextStyle(
                          color: Color(0xFF8D9AA6),
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  String _formatTime(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${_two(h)}:${_two(m)}:${_two(s)}';
    return '${_two(m)}:${_two(s)}';
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}
