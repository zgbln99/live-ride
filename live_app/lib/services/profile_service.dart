import 'package:flutter/foundation.dart';

import '../models/rider_profile.dart';
import 'local_store.dart';

/// Owns rider identity and app preferences and notifies the UI on change.
class ProfileService extends ChangeNotifier {
  static const String _fileName = 'profile.json';

  final LocalStore _store = LocalStore('profile');

  RiderProfile _profile = const RiderProfile();
  bool _loaded = false;

  RiderProfile get profile => _profile;
  bool get isLoaded => _loaded;

  /// Convenience for every caller that just needs a name to publish.
  String get riderName => _profile.effectiveName;

  Future<void> load() async {
    final json = await _store.readJson(_fileName);
    if (json != null) {
      try {
        _profile = RiderProfile.fromJson(json);
      } catch (_) {
        _profile = const RiderProfile();
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> update(RiderProfile profile) async {
    _profile = profile;
    notifyListeners();
    await _store.writeJson(_fileName, profile.toJson());
  }

  /// Called after a successful login so the rider is never anonymous.
  ///
  /// The account name only fills an empty display name: a rider who chose
  /// their own name in the app keeps it.
  Future<void> adoptAccount({String? username, String? name}) async {
    final resolvedUsername = (username ?? '').trim();
    final resolvedName = (name ?? '').trim();
    var next = _profile;
    var changed = false;
    if (resolvedUsername.isNotEmpty && resolvedUsername != next.username) {
      next = next.copyWith(username: resolvedUsername);
      changed = true;
    }
    if (next.displayName.trim().isEmpty) {
      final fallback = resolvedName.isNotEmpty
          ? resolvedName
          : resolvedUsername;
      if (fallback.isNotEmpty) {
        next = next.copyWith(displayName: fallback);
        changed = true;
      }
    }
    if (changed) await update(next);
  }
}
