import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/core/geo.dart';
import 'package:live_ride/models/ride_record.dart';
import 'package:live_ride/models/ride_route.dart';
import 'package:live_ride/models/route/route_preferences.dart';
import 'package:live_ride/models/route/route_waypoint.dart';
import 'package:live_ride/services/routing_service.dart';
import 'package:live_ride/services/sync_service.dart';

RecordedRide _ride() => RecordedRide(
  id: 'ride_abc',
  name: 'Poranna jazda',
  startedAt: DateTime.utc(2026, 5, 1, 7),
  endedAt: DateTime.utc(2026, 5, 1, 8, 30),
  elapsedSeconds: 5400,
  movingSeconds: 5100,
  distanceMeters: 42195,
  elevationGainMeters: 520,
  elevationLossMeters: 510,
  maxSpeedKmh: 58.2,
  averageHeartRate: 146,
  points: [
    for (var i = 0; i < 20; i++)
      RecordedRidePoint(
        lat: 52.0 + i * 0.001,
        lon: 21.0 + i * 0.001,
        recordedAt: DateTime.utc(2026, 5, 1, 7).add(Duration(seconds: i)),
        distanceMeters: i * 10,
      ),
  ],
);

void main() {
  group('ładunek przejazdu', () {
    test('niesie client_id, po którym serwer rozpozna powtórkę', () {
      final json = SyncService.rideToJson(_ride());
      expect(json['client_id'], 'ride_abc');
      expect(json['name'], 'Poranna jazda');
      expect(json['distance_m'], 42195);
      expect(json['point_count'], 20);
    });

    test('ślad idzie jako polilinia, nie jako lista punktów', () {
      final ride = _ride();
      final json = SyncService.rideToJson(ride);
      final encoded = json['track_polyline'] as String;
      expect(encoded, isNotEmpty);

      final decoded = decodeValhallaPolyline(encoded);
      expect(decoded, hasLength(ride.points.length));
      expect(decoded.first.lat, closeTo(52.0, 0.00001));
    });

    test('czas jest w UTC, żeby strefa telefonu nic nie przesuwała', () {
      final json = SyncService.rideToJson(_ride());
      expect(json['started_at'], endsWith('Z'));
      expect(json['ended_at'], endsWith('Z'));
    });

    test('brakujące metryki idą jako zero, nie jako null', () {
      final json = SyncService.rideToJson(_ride());
      expect(json['avg_power'], 0);
      expect(json['avg_cadence'], 0);
      expect(json['calories'], 0);
      expect(json['avg_heart_rate'], 146);
    });

    test('przejazd jest domyślnie prywatny', () {
      expect(SyncService.rideToJson(_ride())['privacy'], 'private');
    });
  });

  group('ładunek trasy', () {
    RideRoute route({RoutePrivacy privacy = RoutePrivacy.private}) => RideRoute(
      id: 'route_abc',
      name: 'Pętla wokół jeziora',
      description: 'Płasko i szybko',
      tags: const ['szosa', 'pętla'],
      privacy: privacy,
      points: [
        for (var i = 0; i < 30; i++)
          GeoPoint(lat: 52.0 + i * 0.001, lon: 21.0, elevation: 100 + i * 1.0),
      ],
      waypoints: [
        const RouteWaypoint(
          point: GeoPoint(lat: 52.0, lon: 21.0),
          name: 'Start',
        ),
      ],
      preferences: const RoutePreferences(),
      updatedAt: DateTime.utc(2026, 5, 1, 12),
    );

    test('niesie geometrię, punkty i preferencje', () {
      final json = SyncService.routeToJson(route());
      expect(json['client_id'], 'route_abc');
      expect((json['polyline'] as String), isNotEmpty);
      expect((json['waypoints'] as List), hasLength(1));
      expect(json['preferences'], isA<Map<String, dynamic>>());
      expect(json['tags'], ['szosa', 'pętla']);
    });

    test('prywatność jedzie taka, jaką ustawił zawodnik', () {
      expect(SyncService.routeToJson(route())['privacy'], 'private');
      expect(
        SyncService.routeToJson(
          route(privacy: RoutePrivacy.unlisted),
        )['privacy'],
        'link',
      );
      expect(
        SyncService.routeToJson(route(privacy: RoutePrivacy.public))['privacy'],
        'public',
      );
    });

    test('znacznik zmiany pozwala serwerowi rozstrzygnąć konflikt', () {
      final json = SyncService.routeToJson(route());
      expect(json['client_updated_at'], '2026-05-01T12:00:00.000Z');
    });
  });
}
