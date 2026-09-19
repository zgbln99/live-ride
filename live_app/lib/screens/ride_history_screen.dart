import 'package:flutter/material.dart';

import '../models/ride_record.dart';

class RideHistoryScreen extends StatelessWidget {
  const RideHistoryScreen({super.key, required this.rides});

  final List<RecordedRide> rides;

  @override
  Widget build(BuildContext context) {
    if (rides.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history, size: 64),
              SizedBox(height: 16),
              Text(
                'Brak zapisanych jazd',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 8),
              Text(
                'Uruchom Start Ride i po zakończeniu przejazd pojawi się tutaj.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: rides.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final ride = rides[index];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => RideSummaryScreen(ride: ride)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.directions_bike),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ride.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${(ride.distanceMeters / 1000).toStringAsFixed(2)} km  •  ${_formatDuration(ride.movingSeconds)}  •  ${ride.averageSpeedKmh.toStringAsFixed(1)} km/h',
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m} min';
  }
}

class RideSummaryScreen extends StatelessWidget {
  const RideSummaryScreen({super.key, required this.ride});

  final RecordedRide ride;

  @override
  Widget build(BuildContext context) {
    final avgHr = ride.averageHeartRate;
    return Scaffold(
      appBar: AppBar(title: const Text('Podsumowanie')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            ride.name,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            '${_two(ride.startedAt.day)}.${_two(ride.startedAt.month)}.${ride.startedAt.year}  ${_two(ride.startedAt.hour)}:${_two(ride.startedAt.minute)}',
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _metric('Dystans', '${(ride.distanceMeters / 1000).toStringAsFixed(2)} km'),
              _metric('Czas', RideHistoryScreen._formatDuration(ride.movingSeconds)),
              _metric('Średnia', '${ride.averageSpeedKmh.toStringAsFixed(1)} km/h'),
              _metric('W górę', '${ride.elevationGainMeters.round()} m'),
              _metric('Punkty GPS', '${ride.points.length}'),
              if (avgHr != null) _metric('Śr. HR', '$avgHr bpm'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) => Container(
        width: 165,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE5E9EE)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6D7A86),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      );

  static String _two(int value) => value.toString().padLeft(2, '0');
}
