import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'dart:async';

import '../core/api_client.dart';
import '../core/geo.dart';
import '../data/settings_dao.dart';
import '../models/live_privacy.dart';
import 'heart_rate_service.dart';
import 'profile_service.dart';
import 'sensor_hub.dart';

/// Owns the LIVE session: creating it, joining one, publishing telemetry and
/// exposing the spectator link.
class LiveSessionController extends ChangeNotifier {
  LiveSessionController(
    this.api,
    this.profile, {

    /// Źródła pomiarów są opcjonalne, tak jak w rzeczywistości: zawodnik bez
    /// paska i bez miernika mocy nadal transmituje pozycję i prędkość.
    this.heartRate,
    SensorHub? sensors,
    SettingsDao? settings,
  }) : _sensors = sensors,
       _settings = settings;

  static const String privacyKey = 'live_privacy';
  static const String shareKey = 'live_share';

  /// Co ile odświeżamy wiadomości grupy. Rzadziej niż telemetrię: wiadomość
  /// sprzed dziesięciu sekund wciąż jest aktualna, pozycja już nie.
  static const Duration messageInterval = Duration(seconds: 10);

  /// Telemetry cadence. Fast enough for a spectator map, slow enough not to
  /// drain a phone that is also navigating.
  static const Duration telemetryInterval = Duration(seconds: 3);

  final ApiClient api;
  final HeartRateService? heartRate;
  final ProfileService profile;
  final SensorHub? _sensors;
  final SettingsDao? _settings;

  LiveSession? _session;
  DateTime? _lastSentAt;
  DateTime? _lastAcceptedAt;
  bool _lastPushFailed = false;
  String? _title;
  LivePrivacy _privacy = const LivePrivacy();
  LiveShareSettings _share = const LiveShareSettings();
  List<LiveMessage> _messages = const [];
  DateTime? _messagesFetchedAt;
  GeoPoint? _meetup;
  String _meetupLabel = '';
  bool _isGroup = false;

  LiveSession? get session => _session;
  bool get isActive => _session != null;
  String? get title => _title;
  String? get joinCode => _session?.joinToken;
  String? get viewerUrl =>
      _session == null ? null : api.viewerUrl(_session!.shareToken);
  DateTime? get lastAcceptedAt => _lastAcceptedAt;
  bool get lastPushFailed => _lastPushFailed;
  LivePrivacy get privacy => _privacy;
  LiveShareSettings get share => _share;
  List<LiveMessage> get messages => List.unmodifiable(_messages);
  GeoPoint? get meetup => _meetup;
  String get meetupLabel => _meetupLabel;
  bool get isGroup => _isGroup;

  Future<void> restore() async {
    final stored = await _settings?.readJson(privacyKey);
    if (stored != null) {
      try {
        _privacy = LivePrivacy.fromJson(stored);
      } catch (_) {
        _privacy = const LivePrivacy();
      }
    }
    final storedShare = await _settings?.readJson(shareKey);
    if (storedShare != null) {
      try {
        _share = LiveShareSettings.fromJson(storedShare);
      } catch (_) {
        _share = const LiveShareSettings();
      }
    }
    notifyListeners();
  }

  /// Tekst, który idzie do systemowego arkusza udostępniania.
  ///
  /// Imię bierze się z profilu, nigdy z kodu — „Marek jedzie teraz" wpisane
  /// na sztywno byłoby kłamstwem u każdego innego zawodnika.
  String shareMessage() {
    final link = viewerUrl ?? '';
    return '${profile.riderName} jedzie teraz na rowerze 🚴\n'
        'Śledź przejazd na żywo w Live Ride:\n$link';
  }

  /// Zmienia widoczność linku albo jego wygasanie.
  ///
  /// Wybór zapisuje się lokalnie także wtedy, gdy nie ma połączenia: kolejna
  /// sesja ma startować z ustawieniem, które zawodnik już wybrał.
  Future<bool> updateShare(LiveShareSettings settings) async {
    _share = settings;
    notifyListeners();
    await _settings?.writeJson(shareKey, settings.toJson());

    final active = _session;
    if (active == null) return true;
    try {
      final result = await api.setLiveShare(
        active.id,
        visibility: settings.visibility.wire,
        expireOnEnd: settings.expiry.expiresOnEnd,
        // 0 czyści datę wygaśnięcia po stronie serwera.
        expireInHours: settings.expiry.hours ?? 0,
      );
      _session = active.copyWith(
        visibility: result['visibility'] as String? ?? settings.visibility.wire,
      );
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Wystawia nowy token i unieważnia każdy rozesłany link.
  Future<bool> rotateShareLink() async {
    final active = _session;
    if (active == null) return false;
    try {
      final result = await api.setLiveShare(active.id, rotateToken: true);
      final token = result['share_token'] as String?;
      if (token == null || token.isEmpty) return false;
      _session = active.copyWith(shareToken: token);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Zmienia ustawienia prywatności.
  ///
  /// Zapis idzie najpierw lokalnie, a dopiero potem na serwer: zawodnik,
  /// który wyłączył udostępnianie tętna w tunelu bez zasięgu, ma prawo
  /// oczekiwać, że zostanie ono wyłączone także po wyjeździe z tunelu.
  Future<void> updatePrivacy(LivePrivacy privacy) async {
    _privacy = privacy;
    notifyListeners();
    await _settings?.writeJson(privacyKey, privacy.toJson());
    final active = _session;
    if (active == null) return;
    try {
      await api.setLivePrivacy(active.id, privacy.toJson());
    } catch (_) {
      // Następny udany push telemetrii i tak wyśle ustawienia ponownie.
    }
  }

  Future<void> setMeetup({GeoPoint? point, String label = ''}) async {
    final active = _session;
    if (active == null) return;
    try {
      await api.setLiveMeetup(
        active.id,
        lat: point?.lat,
        lon: point?.lon,
        label: label,
        clear: point == null,
      );
      _meetup = point;
      _meetupLabel = label;
      _isGroup = true;
      notifyListeners();
    } catch (_) {
      // Punkt zbiórki nie jest krytyczny dla jazdy.
    }
  }

  Future<bool> sendMessage(String body) async {
    final active = _session;
    if (active == null || body.trim().isEmpty) return false;
    try {
      await api.postLiveMessage(active.id, body.trim());
      await refreshMessages(force: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> refreshMessages({bool force = false}) async {
    final active = _session;
    if (active == null) return;
    final last = _messagesFetchedAt;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < messageInterval) {
      return;
    }
    _messagesFetchedAt = DateTime.now();
    try {
      final raw = await api.fetchLiveMessages(active.shareToken);
      _messages = [for (final entry in raw) ?LiveMessage.fromJson(entry)];
      notifyListeners();
    } catch (_) {
      // Brak wiadomości nie może przerwać jazdy.
    }
  }

  Future<LiveSession> create({String? title, String? routeClientId}) async {
    final resolved = (title ?? '').trim().isNotEmpty
        ? title!.trim()
        : '${profile.riderName} · Live Ride';
    final created = await api.createLive(
      title: resolved,
      displayName: profile.riderName,
      routeClientId: routeClientId,
      visibility: _share.visibility.wire,
      expireOnEnd: _share.expiry.expiresOnEnd,
    );
    _session = created;
    _title = resolved;
    _lastSentAt = null;
    _lastAcceptedAt = null;
    _lastPushFailed = false;
    _messages = const [];
    _messagesFetchedAt = null;
    notifyListeners();
    unawaited(api.setLivePrivacy(created.id, _privacy.toJson()));
    // Wygasanie „po X godzinach" ustawia się osobno: przy tworzeniu sesji
    // serwer zna tylko „po zakończeniu".
    final hours = _share.expiry.hours;
    if (hours != null) {
      unawaited(
        api
            .setLiveShare(created.id, expireInHours: hours)
            .catchError((_) => <String, dynamic>{}),
      );
    }
    return created;
  }

  Future<LiveSession> join(String code) async {
    final joined = await api.joinLive(code, displayName: profile.riderName);
    _session = joined;
    _title = 'Joined LIVE';
    _lastSentAt = null;
    _lastAcceptedAt = null;
    _lastPushFailed = false;
    _isGroup = true;
    _messages = const [];
    _messagesFetchedAt = null;
    notifyListeners();
    unawaited(api.setLivePrivacy(joined.id, _privacy.toJson()));
    return joined;
  }

  Future<void> stop() async {
    final active = _session;
    _session = null;
    _title = null;
    _lastSentAt = null;
    _lastAcceptedAt = null;
    _lastPushFailed = false;
    _messages = const [];
    _messagesFetchedAt = null;
    _meetup = null;
    _meetupLabel = '';
    _isGroup = false;
    notifyListeners();
    if (active != null) {
      // Best effort: the session also expires server-side, and a failed stop
      // must never block ending a ride.
      try {
        await api.stopLive(active.id);
      } catch (_) {}
    }
  }

  /// Publishes one telemetry sample. Returns false when the upload failed or
  /// was skipped; navigation and recording never depend on the result.
  Future<bool> pushPosition(
    Position position, {
    required double distanceMeters,
    double elevationGainMeters = 0,

    /// „riding", „paused" albo „stopped". Bez tego publiczna strona nie
    /// odróżni świateł od pauzy ani jednego od utraty zasięgu.
    String state = 'riding',
    int movingSeconds = 0,
    double maxSpeedKmh = 0,
    int batteryPercent = 0,
    int autoPausedSeconds = 0,
    int manualPausedSeconds = 0,

    /// Pomija odczekanie między próbkami.
    ///
    /// Używa tego wyłącznie pierwsza telemetria po udostępnieniu linku:
    /// znajomy, który otworzył go sekundę później, ma zobaczyć zawodnika
    /// od razu, a nie po upływie zwykłego okresu nadawania.
    bool force = false,
  }) async {
    final active = _session;
    if (active == null) return true;

    final now = DateTime.now();
    final last = _lastSentAt;
    if (!force && last != null && now.difference(last) < telemetryInterval) {
      return true;
    }
    _lastSentAt = now;

    try {
      await api.sendTelemetry(active.id, {
        'recorded_at': position.timestamp.toUtc().toIso8601String(),
        'latitude': position.latitude,
        'longitude': position.longitude,
        'speed_kmh': _clamp(
          (position.speed.isFinite ? position.speed : 0) * 3.6,
          0,
          200,
        ),
        'altitude_m': position.altitude.isFinite ? position.altitude : 0,
        'heading_deg': position.heading.isFinite && position.heading >= 0
            ? position.heading
            : 0,
        'accuracy_m': _clamp(
          position.accuracy.isFinite ? position.accuracy : 0,
          0,
          5000,
        ),
        // Prywatność rozstrzyga serwer przy wydawaniu migawki, ale pola,
        // których zawodnik nie udostępnia, w ogóle nie opuszczają telefonu.
        'heart_rate_bpm': _privacy.shareHeartRate
            ? (heartRate?.latestBpm ?? 0)
            : 0,
        'cadence_rpm': _privacy.sharePower
            ? (_sensors?.snapshot.cadenceRpm?.round() ?? 0)
            : 0,
        'power_watts': _privacy.sharePower
            ? (_sensors?.snapshot.powerWatts ?? 0)
            : 0,
        'distance_m': distanceMeters,
        'elevation_gain_m': elevationGainMeters,
        'state': state,
        'moving_seconds': movingSeconds,
        'max_speed_kmh': _clamp(maxSpeedKmh, 0, 200),
        // Bateria wychodzi z telefonu tylko wtedy, gdy zawodnik na to
        // pozwolił — serwer i tak filtruje, ale nieudostępnione pole nie ma
        // powodu opuszczać urządzenia.
        'battery_percent': _privacy.shareBattery ? batteryPercent : 0,
        'auto_paused_seconds': autoPausedSeconds,
        'manual_paused_seconds': manualPausedSeconds,
      });
      _lastAcceptedAt = now;
      _lastPushFailed = false;
      return true;
    } catch (_) {
      _lastPushFailed = true;
      return false;
    }
  }

  double _clamp(double value, double min, double max) {
    if (!value.isFinite) return min;
    return value.clamp(min, max);
  }
}
