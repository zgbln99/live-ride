import 'package:flutter/material.dart';

import '../core/lr_theme.dart';
import '../services/ride_recorder.dart';

/// Start / pause / resume / stop for the ride computer.
///
/// Square buttons, full width, no floating pills: usable with winter gloves
/// and readable at a glance on a handlebar mount.
class RideControls extends StatelessWidget {
  const RideControls({
    super.key,
    required this.state,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    this.onLive,
    this.liveActive = false,
    this.busy = false,
  });

  final RideState state;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final VoidCallback? onLive;
  final bool liveActive;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final paused = state == RideState.paused;
    return Container(
      color: LR.surface,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (onLive != null) ...[
              // Icon only: the label would be the first thing to overflow on a
              // narrow phone, and the colour already says whether LIVE is on.
              _ControlButton(
                icon: Icons.sensors,
                label: '',
                tooltip: liveActive ? 'LIVE is on' : 'Start LIVE',
                onPressed: busy ? null : onLive,
                background: liveActive ? LR.alert : LR.surface,
                foreground: liveActive ? Colors.white : LR.ink,
                border: liveActive ? LR.alert : LR.lineStrong,
                width: 56,
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: _ControlButton(
                icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                label: paused ? 'RESUME' : 'PAUSE',
                onPressed: busy ? null : (paused ? onResume : onPause),
                background: paused ? LR.accent : LR.surface,
                foreground: LR.ink,
                border: paused ? LR.accentDeep : LR.lineStrong,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ControlButton(
                icon: Icons.stop_rounded,
                label: busy ? 'SAVING' : 'FINISH',
                onPressed: busy ? null : onStop,
                background: LR.ink,
                foreground: Colors.white,
                border: LR.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.background,
    required this.foreground,
    required this.border,
    this.width,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final String? tooltip;
  final VoidCallback? onPressed;
  final Color background;
  final Color foreground;
  final Color border;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: width,
      height: 56,
      child: Material(
        color: onPressed == null ? LR.panel : background,
        borderRadius: BorderRadius.circular(5),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(5),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: onPressed == null ? LR.line : border),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: onPressed == null ? LR.muted : foreground,
                ),
                if (label.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                        color: onPressed == null ? LR.muted : foreground,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    final message = tooltip;
    return message == null ? button : Tooltip(message: message, child: button);
  }
}
