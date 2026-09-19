import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/lr_theme.dart';
import '../../services/app_services.dart';
import '../../services/spotify_service.dart';
import '../../widgets/lr_common.dart';
import '../../widgets/music_controls.dart';

/// Music for the ride: Spotify sign-in, now playing, transport, devices and
/// somewhere to start from.
class MusicTab extends StatefulWidget {
  const MusicTab({super.key});

  @override
  State<MusicTab> createState() => _MusicTabState();
}

class _MusicTabState extends State<MusicTab> {
  late final SpotifyService _spotify = AppServices.of(context).spotify;
  final TextEditingController _clientIdField = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _clientIdField.text = _spotify.clientId;
      if (_spotify.isConnected) {
        _spotify.startPolling();
        unawaited(_spotify.refreshDevices());
        unawaited(_spotify.refreshShortcuts());
      }
    });
  }

  @override
  void dispose() {
    _spotify.stopPolling();
    _clientIdField.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on SpotifyException catch (e) {
      if (mounted) showLrMessage(context, e.message, error: true);
    } catch (e) {
      if (mounted) showLrMessage(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _spotify,
    builder: (context, _) => switch (_spotify.status) {
      SpotifyStatus.unconfigured => _setupView(),
      SpotifyStatus.signedOut => _signInView(),
      SpotifyStatus.connecting => const Center(
        child: CircularProgressIndicator(),
      ),
      SpotifyStatus.connected => _playerView(),
    },
  );

  // ----------------------------------------------------------------- setup

  Widget _setupView() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
    children: [
      _hero(
        'Connect Spotify',
        'Live Ride controls whatever Spotify is already playing — on this '
            'phone, a speaker, or a head unit — so you can skip a track '
            'without leaving the ride screen.',
      ),
      const SizedBox(height: 22),
      const LrSectionHeader(title: 'One-time setup'),
      LrPanel(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Spotify requires every app to use its own client ID. Live Ride '
              'ships without one on purpose: no shared key, no rate limit you '
              'do not control, nothing secret compiled into the app.',
              style: LR.body.copyWith(height: 1.45, fontSize: 13),
            ),
            const SizedBox(height: 16),
            _step(1, 'Open developer.spotify.com/dashboard and create an app.'),
            _step(2, 'Add this exact redirect URI:'),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 2, 0, 12),
              child: _copyRow(SpotifyService.redirectUri),
            ),
            _step(3, 'Tick the Web API box and save.'),
            _step(4, 'Copy the client ID and paste it below.'),
            const SizedBox(height: 10),
            TextField(
              controller: _clientIdField,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Spotify client ID',
                hintText: '32 characters',
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      await _spotify.setClientId(_clientIdField.text);
                      if (_spotify.isConfigured) await _spotify.connect();
                    }),
              child: const Text('SAVE AND CONNECT'),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _signInView() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
    children: [
      _hero(
        'Connect Spotify',
        'Sign in once. Live Ride only asks for what it needs to show the '
            'track and work the transport controls.',
      ),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: _busy ? null : () => _run(_spotify.connect),
        icon: const Icon(Icons.link, size: 18),
        label: const Text('CONNECT SPOTIFY'),
      ),
      const SizedBox(height: 12),
      TextButton(
        onPressed: () async {
          await _spotify.setClientId('');
          if (mounted) setState(() {});
        },
        child: const Text('Use a different client ID'),
      ),
      if (_spotify.lastError != null) ...[
        const SizedBox(height: 16),
        _errorPanel(_spotify.lastError!),
      ],
      const SizedBox(height: 26),
      const LrSectionHeader(title: 'What Live Ride asks for'),
      LrPanel(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _permission('Read what is playing', 'to show the track on screen'),
            _permission('Control playback', 'play, pause, skip, shuffle'),
            _permission(
              'Read recently played and playlists',
              'so there is something to start from',
            ),
            const SizedBox(height: 4),
            Text(
              'Sign-in runs in the system browser sheet, so your Spotify '
              'password is never seen by Live Ride.',
              style: LR.body.copyWith(fontSize: 12, height: 1.4),
            ),
          ],
        ),
      ),
    ],
  );

  // ---------------------------------------------------------------- player

  Widget _playerView() {
    final track = _spotify.nowPlaying;
    return RefreshIndicator(
      onRefresh: () async {
        await _spotify.refreshNowPlaying();
        await _spotify.refreshDevices();
        await _spotify.refreshShortcuts();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          LrPanel(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            accentEdge: track?.isPlaying ?? false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (track == null)
                  Row(
                    children: [
                      const Artwork(url: null, size: 72),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Nothing playing',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'Start a track in Spotify once. Live Ride takes '
                              'over the controls from there.',
                              style: LR.body.copyWith(
                                fontSize: 12.5,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  NowPlayingCard(track: track),
                const SizedBox(height: 16),
                TransportBar(
                  isPlaying: track?.isPlaying ?? false,
                  busy: _busy,
                  onPrevious: () => _run(_spotify.previous),
                  onPlayPause: () => _run(_spotify.playPause),
                  onNext: () => _run(_spotify.next),
                ),
                if (track != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run(
                                () => _spotify.setShuffle(!track.shuffle),
                              ),
                        icon: Icon(
                          Icons.shuffle,
                          size: 17,
                          color: track.shuffle ? LR.accentDeep : LR.muted,
                        ),
                        label: Text(
                          track.shuffle ? 'SHUFFLE ON' : 'SHUFFLE OFF',
                          style: TextStyle(
                            color: track.shuffle ? LR.accentDeep : LR.muted,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (track.volumePercent != null) ...[
                        const Icon(
                          Icons.volume_down,
                          size: 18,
                          color: LR.muted,
                        ),
                        SizedBox(
                          width: 130,
                          child: Slider(
                            value: track.volumePercent!.toDouble(),
                            max: 100,
                            onChanged: (_) {},
                            onChangeEnd: (value) =>
                                _run(() => _spotify.setVolume(value.round())),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (!_spotify.isPremium) ...[
            const SizedBox(height: 12),
            _errorPanel(
              'This Spotify account is not Premium. Spotify only allows other '
              'apps to control playback on Premium, so the transport buttons '
              'will report an error.',
            ),
          ],
          if (_spotify.lastError != null) ...[
            const SizedBox(height: 12),
            _errorPanel(_spotify.lastError!),
          ],
          const SizedBox(height: 24),
          LrSectionHeader(
            title: 'Play on',
            trailing: TextButton(
              onPressed: () => _run(_spotify.refreshDevices),
              child: const Text('REFRESH'),
            ),
          ),
          _deviceList(),
          const SizedBox(height: 24),
          const LrSectionHeader(title: 'Start something'),
          _shortcutGrid(),
          const SizedBox(height: 24),
          LrPanel(
            padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
            child: Row(
              children: [
                const Icon(Icons.account_circle_outlined, color: LR.inkSoft),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _spotify.displayName ?? 'Spotify account',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text('Connected', style: LR.body.copyWith(fontSize: 12)),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _run(_spotify.disconnect),
                  child: const Text('DISCONNECT'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _deviceList() {
    final devices = _spotify.devices;
    if (devices.isEmpty) {
      return LrPanel(
        padding: const EdgeInsets.all(18),
        child: Text(
          'No Spotify devices are awake. Open Spotify on this phone, a '
          'speaker or a computer and it appears here.',
          style: LR.body,
        ),
      );
    }
    return Column(
      children: [
        for (final device in devices) ...[
          LrPanel(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            accentEdge: device.isActive,
            onTap: _busy ? null : () => _run(() => _spotify.transferTo(device)),
            child: Row(
              children: [
                Icon(_deviceIcon(device.type), size: 19, color: LR.inkSoft),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        device.isActive ? 'Playing here' : device.type,
                        style: LR.body.copyWith(fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                if (device.isActive)
                  const Icon(Icons.graphic_eq, size: 17, color: LR.accentDeep),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  IconData _deviceIcon(String type) => switch (type.toLowerCase()) {
    'smartphone' => Icons.smartphone,
    'computer' => Icons.laptop_mac,
    'speaker' => Icons.speaker,
    'tv' => Icons.tv,
    'automobile' => Icons.directions_car,
    _ => Icons.devices_other,
  };

  Widget _shortcutGrid() {
    final shortcuts = _spotify.shortcuts;
    if (shortcuts.isEmpty) {
      return LrPanel(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Your playlists and recently played appear here.',
                style: LR.body,
              ),
            ),
            TextButton(
              onPressed: () => _run(_spotify.refreshShortcuts),
              child: const Text('LOAD'),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: shortcuts.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 2.5,
      ),
      itemBuilder: (context, index) {
        final item = shortcuts[index];
        return LrPanel(
          padding: const EdgeInsets.all(8),
          onTap: _busy ? null : () => _run(() => _spotify.playContext(item)),
          child: Row(
            children: [
              Artwork(url: item.artworkUrl, size: 44),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LR.body.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------- pieces

  Widget _hero(String title, String body) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: LR.night,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.graphic_eq, color: LR.accent, size: 18),
            const SizedBox(width: 8),
            Text(
              'MUSIC',
              style: TextStyle(
                color: LR.accent,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.6,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            height: 1.15,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          style: const TextStyle(
            color: Color(0xFF9BAEBD),
            fontSize: 13,
            height: 1.45,
          ),
        ),
      ],
    ),
  );

  Widget _step(int number, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: LR.ink,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            '$number',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              text,
              style: const TextStyle(fontSize: 13.5, height: 1.35),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _permission(String title, String why) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check, size: 16, color: LR.go),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 13, color: LR.ink),
              children: [
                TextSpan(
                  text: title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                TextSpan(
                  text: ' — $why',
                  style: const TextStyle(color: LR.muted),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _copyRow(String value) => LrPanel(
    color: LR.panel,
    padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              fontFamily: 'Menlo',
            ),
          ),
        ),
        IconButton(
          tooltip: 'Copy',
          icon: const Icon(Icons.copy, size: 16),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: value));
            if (mounted) showLrMessage(context, 'Redirect URI copied');
          },
        ),
      ],
    ),
  );

  Widget _errorPanel(String message) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: LR.alert.withValues(alpha: 0.08),
      border: Border.all(color: LR.alert),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, size: 18, color: LR.alert),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: LR.body.copyWith(fontSize: 13, color: LR.ink, height: 1.4),
          ),
        ),
      ],
    ),
  );
}
