/// What Spotify is playing right now.
class NowPlaying {
  NowPlaying({
    required this.title,
    required this.artist,
    required this.isPlaying,
    this.album,
    this.artworkUrl,
    this.trackId,
    this.durationMs = 0,
    this.progressMs = 0,
    this.deviceName,
    this.deviceId,
    this.shuffle = false,
    this.repeat = 'off',
    this.volumePercent,
    DateTime? sampledAt,
  }) : sampledAt = sampledAt ?? DateTime.now();

  final String title;
  final String artist;
  final String? album;
  final String? artworkUrl;
  final String? trackId;
  final bool isPlaying;
  final int durationMs;
  final int progressMs;
  final String? deviceName;
  final String? deviceId;
  final bool shuffle;
  final String repeat;
  final int? volumePercent;

  /// When this snapshot was taken, so progress can advance between polls
  /// instead of ticking in five-second jumps.
  final DateTime sampledAt;

  /// Progress right now, extrapolated from the last snapshot.
  int get liveProgressMs {
    if (!isPlaying || durationMs <= 0) return progressMs;
    final elapsed = DateTime.now().difference(sampledAt).inMilliseconds;
    final value = progressMs + (elapsed < 0 ? 0 : elapsed);
    return value > durationMs ? durationMs : value;
  }

  double get fraction =>
      durationMs <= 0 ? 0 : (liveProgressMs / durationMs).clamp(0.0, 1.0);

  factory NowPlaying.fromJson(Map<String, dynamic> json) {
    final item = json['item'];
    final device = json['device'];
    final album = item is Map ? item['album'] : null;
    final images = album is Map ? album['images'] : null;
    String? artwork;
    if (images is List && images.isNotEmpty) {
      final first = images.first;
      if (first is Map) artwork = first['url'] as String?;
    }
    final artists = item is Map ? item['artists'] : null;
    final artistNames = artists is List
        ? artists
              .whereType<Map>()
              .map((artist) => artist['name'] as String? ?? '')
              .where((name) => name.isNotEmpty)
              .toList()
        : const <String>[];

    return NowPlaying(
      title: item is Map ? (item['name'] as String? ?? 'Unknown') : 'Nothing',
      artist: artistNames.isEmpty ? '' : artistNames.join(', '),
      album: album is Map ? album['name'] as String? : null,
      artworkUrl: artwork,
      trackId: item is Map ? item['id'] as String? : null,
      isPlaying: json['is_playing'] as bool? ?? false,
      durationMs: item is Map ? (item['duration_ms'] as num? ?? 0).toInt() : 0,
      progressMs: (json['progress_ms'] as num? ?? 0).toInt(),
      deviceName: device is Map ? device['name'] as String? : null,
      deviceId: device is Map ? device['id'] as String? : null,
      shuffle: json['shuffle_state'] as bool? ?? false,
      repeat: json['repeat_state'] as String? ?? 'off',
      volumePercent: device is Map
          ? (device['volume_percent'] as num?)?.toInt()
          : null,
      sampledAt: DateTime.now(),
    );
  }
}

/// A device Spotify can play on.
class SpotifyDevice {
  const SpotifyDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.isActive,
    this.volumePercent,
  });

  final String id;
  final String name;
  final String type;
  final bool isActive;
  final int? volumePercent;

  factory SpotifyDevice.fromJson(Map<String, dynamic> json) => SpotifyDevice(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? 'Device',
    type: json['type'] as String? ?? 'Unknown',
    isActive: json['is_active'] as bool? ?? false,
    volumePercent: (json['volume_percent'] as num?)?.toInt(),
  );
}

/// A playlist or a recently played context the rider can start from.
class MusicItem {
  const MusicItem({
    required this.uri,
    required this.title,
    required this.subtitle,
    this.artworkUrl,
  });

  final String uri;
  final String title;
  final String subtitle;
  final String? artworkUrl;
}
