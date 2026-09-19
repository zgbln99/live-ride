import 'package:sqflite/sqflite.dart';

import '../models/bike.dart';
import 'database.dart';

/// Garaż w bazie: rowery, ich liczniki i komponenty serwisowe.
class BikeDao {
  BikeDao(this._database);

  final LiveRideDatabase _database;

  Future<List<Bike>> listBikes() async {
    final db = await _database.open();
    final rows = await db.query(
      'bikes',
      orderBy: 'is_default DESC, created_at ASC',
    );
    return [for (final row in rows) _bikeFromRow(row)];
  }

  Future<Bike?> findBike(String id) async {
    final db = await _database.open();
    final rows = await db.query(
      'bikes',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _bikeFromRow(rows.first);
  }

  Future<Bike?> defaultBike() async {
    final bikes = await listBikes();
    if (bikes.isEmpty) return null;
    return bikes.firstWhere(
      (bike) => bike.isDefault,
      orElse: () => bikes.first,
    );
  }

  Future<void> saveBike(Bike bike) async {
    final db = await _database.open();
    await db.transaction((txn) async {
      if (bike.isDefault) {
        // Tylko jeden rower może być domyślny; inaczej „który mam dziś"
        // rozstrzygałaby kolejność wierszy.
        await txn.update('bikes', {'is_default': 0});
      }
      await txn.insert(
        'bikes',
        _bikeToRow(bike),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> deleteBike(String id) async {
    final db = await _database.open();
    // Komponenty znikają razem z rowerem dzięki ON DELETE CASCADE.
    await db.delete('bikes', where: 'id = ?', whereArgs: [id]);
  }

  /// Dolicza przejechany dystans do licznika roweru.
  ///
  /// Liczy baza, a nie Dart: dwa przejazdy zakończone równocześnie nie mogą
  /// nadpisać sobie licznika.
  Future<void> addDistance(String bikeId, double meters) async {
    if (meters <= 0) return;
    final db = await _database.open();
    await db.rawUpdate(
      'UPDATE bikes SET odometer_meters = odometer_meters + ? WHERE id = ?',
      [meters, bikeId],
    );
  }

  Future<void> setOdometer(String bikeId, double meters) async {
    final db = await _database.open();
    await db.update(
      'bikes',
      {'odometer_meters': meters},
      where: 'id = ?',
      whereArgs: [bikeId],
    );
  }

  // ------------------------------------------------------------ komponenty

  Future<List<BikeComponent>> listComponents(String bikeId) async {
    final db = await _database.open();
    final rows = await db.query(
      'bike_components',
      where: 'bike_id = ?',
      whereArgs: [bikeId],
      orderBy: 'installed_at DESC',
    );
    return [for (final row in rows) _componentFromRow(row)];
  }

  Future<void> saveComponent(BikeComponent component) async {
    final db = await _database.open();
    await db.insert(
      'bike_components',
      _componentToRow(component),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteComponent(String id) async {
    final db = await _database.open();
    await db.delete('bike_components', where: 'id = ?', whereArgs: [id]);
  }

  // -------------------------------------------------------------- mapowanie

  Map<String, Object?> _bikeToRow(Bike bike) => {
    'id': bike.id,
    'name': bike.name,
    'kind': bike.kind.name,
    'weight_kg': bike.weightKg,
    'wheel_circumference_mm': bike.wheelCircumferenceMm,
    'photo_path': bike.photoPath,
    'odometer_meters': bike.odometerMeters,
    'is_default': bike.isDefault ? 1 : 0,
    'created_at': bike.createdAt.millisecondsSinceEpoch,
  };

  Bike _bikeFromRow(Map<String, Object?> row) => Bike(
    id: '${row['id']}',
    name: '${row['name']}',
    kind: BikeKind.parse(row['kind'] as String?),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (row['created_at'] as num?)?.toInt() ?? 0,
    ),
    weightKg: (row['weight_kg'] as num?)?.toDouble(),
    wheelCircumferenceMm: (row['wheel_circumference_mm'] as num?)?.toInt(),
    photoPath: row['photo_path'] as String?,
    odometerMeters: (row['odometer_meters'] as num?)?.toDouble() ?? 0,
    isDefault: ((row['is_default'] as num?)?.toInt() ?? 0) == 1,
  );

  Map<String, Object?> _componentToRow(BikeComponent component) => {
    'id': component.id,
    'bike_id': component.bikeId,
    'name': component.name,
    'kind': component.kind.name,
    'installed_at': component.installedAt.millisecondsSinceEpoch,
    'odometer_at_install_meters': component.odometerAtInstallMeters,
    'limit_meters': component.limitMeters,
    'limit_days': component.limitDays,
  };

  BikeComponent _componentFromRow(Map<String, Object?> row) => BikeComponent(
    id: '${row['id']}',
    bikeId: '${row['bike_id']}',
    name: '${row['name']}',
    kind: ComponentKind.parse(row['kind'] as String?),
    installedAt: DateTime.fromMillisecondsSinceEpoch(
      (row['installed_at'] as num?)?.toInt() ?? 0,
    ),
    odometerAtInstallMeters:
        (row['odometer_at_install_meters'] as num?)?.toDouble() ?? 0,
    limitMeters: (row['limit_meters'] as num?)?.toDouble(),
    limitDays: (row['limit_days'] as num?)?.toInt(),
  );
}
