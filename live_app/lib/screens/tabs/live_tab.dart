import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/formatters.dart';
import '../../core/lr_theme.dart';
import '../../i18n/strings.dart';
import '../../services/app_services.dart';
import '../../services/heart_rate_service.dart';
import '../../services/live_service.dart';
import '../../widgets/lr_common.dart';
import '../live_sheet.dart';
import '../whoop_screen.dart';

/// LIVE session status, the spectator link, and heart-rate sensors.
class LiveTab extends StatefulWidget {
  const LiveTab({super.key});

  @override
  State<LiveTab> createState() => _LiveTabState();
}

class _LiveTabState extends State<LiveTab> {
  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);

    return AnimatedBuilder(
      animation: Listenable.merge([
        services.live,
        services.recorder,
        services.profile,
      ]),
      builder: (context, _) {
        final live = services.live;
        final session = live.session;
        final metrics = services.recorder.metrics;
        final metric = services.profile.profile.metricUnits;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            LrSectionHeader(title: S.liveTracking),
            LrPanel(
              padding: const EdgeInsets.all(18),
              accentEdge: session != null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          session == null
                              ? S.notBroadcasting
                              : live.title ?? S.live,
                          style: LR.title.copyWith(fontSize: 19),
                        ),
                      ),
                      if (session != null)
                        LrStatusChip(
                          label: live.lastPushFailed ? S.reconnecting : S.live,
                          color: live.lastPushFailed ? LR.inkSoft : LR.alert,
                          filled: !live.lastPushFailed,
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    session == null
                        ? S.liveDescription
                        : S.ridingAsTelemetry(
                            services.profile.riderName,
                            LiveSessionController.telemetryInterval.inSeconds,
                          ),
                    style: LR.body.copyWith(height: 1.45),
                  ),
                  if (session != null) ...[
                    const SizedBox(height: 16),
                    _copyRow(S.joinCode, session.joinToken),
                    const SizedBox(height: 10),
                    _copyRow(S.spectatorLink, live.viewerUrl ?? ''),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: LrStat(
                            label: S.fieldSpeed,
                            value: Fmt.speed(metrics.speedKmh, metric: metric),
                            unit: Fmt.speedUnit(metric: metric),
                          ),
                        ),
                        Expanded(
                          child: LrStat(
                            label: S.distance,
                            value: Fmt.distance(
                              metrics.distanceMeters,
                              metric: metric,
                            ),
                            unit: Fmt.distanceUnit(metric: metric),
                          ),
                        ),
                        Expanded(
                          child: LrStat(
                            label: 'HR',
                            value: metrics.heartRate?.toString() ?? '--',
                            unit: 'bpm',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      live.lastAcceptedAt == null
                          ? S.waitingForFirstUpload
                          : 'Last update ${Fmt.clock(live.lastAcceptedAt!)}',
                      style: LR.fieldLabel.copyWith(fontSize: 10),
                    ),
                  ],
                  const SizedBox(height: 18),
                  if (session == null)
                    FilledButton.icon(
                      onPressed: () => _openSheet(services),
                      icon: const Icon(Icons.sensors, size: 18),
                      label: Text(S.startOrJoinLive),
                    )
                  else ...[
                    FilledButton.icon(
                      onPressed: () => SharePlus.instance.share(
                        ShareParams(
                          text: live.viewerUrl ?? '',
                          subject: S.followMyRide,
                        ),
                      ),
                      icon: const Icon(Icons.ios_share, size: 18),
                      label: Text(S.shareTheLink),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await live.stop();
                        if (mounted) setState(() {});
                      },
                      icon: const Icon(Icons.stop_circle_outlined, size: 18),
                      label: Text(S.endLive),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: LR.alert,
                        side: const BorderSide(color: LR.alert),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            LrSectionHeader(title: S.heartRate),
            _heartRatePanel(services),
          ],
        );
      },
    );
  }

  /// A summary that answers "is my strap working" and opens the full
  /// heart-rate screen for anything more.
  Widget _heartRatePanel(AppServices services) {
    final hr = services.heartRate;
    return AnimatedBuilder(
      animation: hr,
      builder: (context, _) => LrPanel(
        padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
        accentEdge: hr.isConnected && !hr.isStale,
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const WhoopScreen())),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.favorite,
                  color: hr.latestBpm == null ? LR.lineStrong : LR.alert,
                  size: 26,
                ),
                const SizedBox(width: 12),
                Text(
                  hr.latestBpm?.toString() ?? '--',
                  style: LR.fieldValue(34),
                ),
                const SizedBox(width: 6),
                Text('bpm', style: LR.fieldUnit),
                const Spacer(),
                Text(switch (hr.status) {
                  HeartRateStatus.streaming => hr.isStale ? S.noBeat : S.live,
                  HeartRateStatus.waiting => S.connected,
                  HeartRateStatus.connecting => S.connecting,
                  HeartRateStatus.reconnecting => S.reconnecting,
                  HeartRateStatus.scanning => S.scanning,
                  HeartRateStatus.idle => S.notConnected,
                }, style: LR.fieldLabel.copyWith(fontSize: 10)),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, size: 18, color: LR.muted),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              hr.isConnected
                  ? '${S.connectedTo(hr.connectedName ?? S.heartRateStrap)}'
                        '${hr.batteryPercent == null ? '' : ' · ${S.sensorBattery(hr.batteryPercent!)}'}'
                  : S.connectStrapHint,
              style: LR.body.copyWith(fontSize: 12.5, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _copyRow(String label, String value) => LrPanel(
    color: LR.panel,
    padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: LR.fieldLabel),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: S.copy,
          icon: const Icon(Icons.copy, size: 17),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: value));
            if (mounted) showLrMessage(context, '$label copied');
          },
        ),
      ],
    ),
  );

  Future<void> _openSheet(AppServices services) async {
    await showLiveSheet(context, services);
    if (mounted) setState(() {});
  }
}
