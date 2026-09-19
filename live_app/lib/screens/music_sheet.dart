import 'dart:async';

import 'package:flutter/material.dart';

import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../services/app_services.dart';
import '../services/spotify_service.dart';
import '../widgets/lr_common.dart';
import '../widgets/music_controls.dart';

/// Skip a track without leaving the ride.
///
/// Deliberately the smallest possible surface: what is playing, and three
/// buttons big enough for a gloved thumb. Anything more belongs on the Music
/// tab, where the rider is not moving.
Future<void> showMusicSheet(BuildContext context, AppServices services) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => _MusicSheet(spotify: services.spotify),
  );
}

class _MusicSheet extends StatefulWidget {
  const _MusicSheet({required this.spotify});

  final SpotifyService spotify;

  @override
  State<_MusicSheet> createState() => _MusicSheetState();
}

class _MusicSheetState extends State<_MusicSheet> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.spotify.startPolling(interval: const Duration(seconds: 4));
  }

  @override
  void dispose() {
    widget.spotify.stopPolling();
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
  Widget build(BuildContext context) => SafeArea(
    child: AnimatedBuilder(
      animation: widget.spotify,
      builder: (context, _) {
        final track = widget.spotify.nowPlaying;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LrSectionHeader(title: S.music),
              if (track == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    widget.spotify.isConnected
                        ? S.nothingPlayingHint
                        : S.connectSpotifyOnMusicTab,
                    style: LR.body.copyWith(height: 1.4),
                  ),
                )
              else
                NowPlayingCard(track: track, artSize: 56),
              const SizedBox(height: 16),
              TransportBar(
                isPlaying: track?.isPlaying ?? false,
                busy: _busy || !widget.spotify.isConnected,
                height: 66,
                onPrevious: () => _run(widget.spotify.previous),
                onPlayPause: () => _run(widget.spotify.playPause),
                onNext: () => _run(widget.spotify.next),
              ),
            ],
          ),
        );
      },
    ),
  );
}
