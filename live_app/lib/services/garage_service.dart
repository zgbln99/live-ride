import 'package:flutter/foundation.dart';

import '../data/bike_dao.dart';
import '../models/bike.dart';

/// Garaż: rowery, liczniki i przypomnienia o serwisie.
class GarageService extends ChangeNotifier {
  GarageService(this._dao);

  final BikeDao _dao;

  List<Bike> _bikes = const [];
  final Map<String, List<BikeComponent>> _components = {};
  String? _activeBikeId;
  bool _loaded = false;

  List<Bike> get bikes => List.unmodifiable(_bikes);
  bool get isLoaded => _loaded;

  /// Rower, na którym się dziś jedzie. Null, gdy garaż jest pusty —
  /// aplikacja działa bez rowerów, po prostu nie liczy przebiegu.
  Bike? get activeBike {
    if (_bikes.isEmpty) return null;
    final id = _activeBikeId;
    if (id != null) {
      for (final bike in _bikes) {
        if (bike.id == id) return bike;
      }
    }
    return _bikes.firstWhere(
      (bike) => bike.isDefault,
      orElse: () => _bikes.first,
    );
  }

  List<BikeComponent> componentsOf(String bikeId) =>
      List.unmodifiable(_components[bikeId] ?? const []);

  /// Komponenty po terminie albo tuż przed nim, na wszystkich rowerach.
  List<({Bike bike, BikeComponent component, double wear})> get dueSoon {
    final now = DateTime.now();
    final result = <({Bike bike, BikeComponent component, double wear})>[];
    for (final bike in _bikes) {
      for (final component in _components[bike.id] ?? const <BikeComponent>[]) {
        final wear = component.wear(bike.odometerMeters, now);
        if (wear != null && wear >= 0.85) {
          result.add((bike: bike, component: component, wear: wear));
        }
      }
    }
    result.sort((a, b) => b.wear.compareTo(a.wear));
    return List.unmodifiable(result);
  }

  Future<void> load() async {
    _bikes = await _dao.listBikes();
    _components.clear();
    for (final bike in _bikes) {
      _components[bike.id] = await _dao.listComponents(bike.id);
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> selectBike(String? id) async {
    _activeBikeId = id;
    notifyListeners();
  }

  Future<void> saveBike(Bike bike) async {
    await _dao.saveBike(bike);
    await load();
  }

  Future<void> deleteBike(String id) async {
    await _dao.deleteBike(id);
    if (_activeBikeId == id) _activeBikeId = null;
    await load();
  }

  Future<void> setOdometer(String bikeId, double meters) async {
    await _dao.setOdometer(bikeId, meters);
    await load();
  }

  Future<void> saveComponent(BikeComponent component) async {
    await _dao.saveComponent(component);
    await load();
  }

  Future<void> deleteComponent(String id) async {
    await _dao.deleteComponent(id);
    await load();
  }

  /// Zeruje przebieg komponentu — to, co robi wymiana łańcucha.
  Future<void> resetComponent(BikeComponent component) async {
    final bike = _bikes
        .where((bike) => bike.id == component.bikeId)
        .firstOrNull;
    await _dao.saveComponent(
      BikeComponent(
        id: component.id,
        bikeId: component.bikeId,
        name: component.name,
        kind: component.kind,
        installedAt: DateTime.now(),
        odometerAtInstallMeters: bike?.odometerMeters ?? 0,
        limitMeters: component.limitMeters,
        limitDays: component.limitDays,
      ),
    );
    await load();
  }

  /// Dolicza dystans zakończonego przejazdu do licznika roweru.
  Future<void> recordRide({
    required String? bikeId,
    required double distanceMeters,
  }) async {
    final id = bikeId ?? activeBike?.id;
    if (id == null || distanceMeters <= 0) return;
    await _dao.addDistance(id, distanceMeters);
    await load();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
