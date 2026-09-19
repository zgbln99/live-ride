import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/lr_theme.dart';
import '../models/music.dart';

String formatTrackTime(int milliseconds) {
  final seconds = (milliseconds / 1000).round();
  final minutes = seconds ~/ 60;
  return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// Album art with a graceful fallback: a rider on a bike should never see a
/// broken-image icon because a CDN was slow.
class Artwork extends StatelessWidget {
  const Artwork({super.key, required this.url, this.size = 64});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      color: LR.panel,
      alignment: Alignment.center,
      child: Icon(Icons.music_note, size: size * 0.4, color: LR.lineStrong),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: url == null
          ? placeholder
          : Image.network(
              url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => placeholder,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : placeholder,
            ),
    );
  }
}

/// The now-playing block: art, track, artist, and a progress line that keeps
/// moving between polls.
class NowPlayingCard extends StatelessWidget {
  const NowPlayingCard({
    super.key,
    required this.track,
    this.artSize = 72,
    this.showProgress = true,
  });

  final NowPlaying track;
  final double artSize;
  final bool showProgress;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Artwork(url: track.artworkUrl, size: artSize),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LR.body.copyWith(fontSize: 13),
                ),
                if (track.deviceName != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.speaker_outlined,
                        size: 13,
                        color: LR.muted,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          track.deviceName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: LR.fieldLabel.copyWith(fontSize: 9.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      if (showProgress) ...[
        const SizedBox(height: 14),
        _Progress(track: track),
      ],
    ],
  );
}

/// A one-second ticker so the progress line advances smoothly while the API is
/// only polled every few seconds.
class _Progress extends StatefulWidget {
  const _Progress({required this.track});

  final NowPlaying track;

  @override
  State<_Progress> createState() => _ProgressState();
}

class _ProgressState extends State<_Progress>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) {
    if (widget.track.isPlaying && mounted) setState(() {});
  })..start();

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: widget.track.fraction,
          minHeight: 3,
          backgroundColor: LR.line,
          valueColor: const AlwaysStoppedAnimation(LR.accentDeep),
        ),
      ),
      const SizedBox(height: 6),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            formatTrackTime(widget.track.liveProgressMs),
            style: LR.fieldLabel.copyWith(fontSize: 9.5),
          ),
          Text(
            formatTrackTime(widget.track.durationMs),
            style: LR.fieldLabel.copyWith(fontSize: 9.5),
          ),
        ],
      ),
    ],
  );
}

/// Transport controls sized for a gloved thumb on a handlebar.
class TransportBar extends StatelessWidget {
  const TransportBar({
    super.key,
    required this.isPlaying,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
    this.busy = false,
    this.height = 62,
  });

  final bool isPlaying;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final bool busy;
  final double height;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _Button(
          icon: Icons.skip_previous_rounded,
          onPressed: busy ? null : onPrevious,
          height: height,
          semanticLabel: 'Previous track',
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        flex: 2,
        child: _Button(
          icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          onPressed: busy ? null : onPlayPause,
          height: height,
          filled: true,
          semanticLabel: isPlaying ? 'Pause' : 'Play',
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _Button(
          icon: Icons.skip_next_rounded,
          onPressed: busy ? null : onNext,
          height: height,
          semanticLabel: 'Next track',
        ),
      ),
    ],
  );
}

class _Button extends StatelessWidget {
  const _Button({
    required this.icon,
    required this.onPressed,
    required this.height,
    required this.semanticLabel,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double height;
  final String semanticLabel;
  final bool filled;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticLabel,
    child: SizedBox(
      height: height,
      child: Material(
        color: onPressed == null
            ? LR.panel
            : filled
            ? LR.ink
            : LR.surface,
        borderRadius: BorderRadius.circular(5),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(5),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: onPressed == null
                    ? LR.line
                    : filled
                    ? LR.ink
                    : LR.lineStrong,
              ),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(
              icon,
              size: filled ? 30 : 24,
              color: onPressed == null
                  ? LR.muted
                  : filled
                  ? Colors.white
                  : LR.ink,
            ),
          ),
        ),
      ),
    ),
  );
}
