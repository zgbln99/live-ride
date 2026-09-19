import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/formatters.dart';
import '../../core/lr_theme.dart';
import '../../services/app_services.dart';
import '../../services/heart_rate_service.dart';
import '../../services/live_service.dart';
import '../../widgets/lr_common.dart';
import '../live_sheet.dart';

/// LIVE session status, the spectator link, and heart-rate sensors.
class LiveTab extends StatefulWidget {
  const LiveTab({super.key});

  @override
  State<LiveTab> createState() => _LiveTabState();
}

class _LiveTabState extends State<LiveTab> {
  bool _scanning = false;

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
            const LrSectionHeader(title: 'Live tracking'),
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
                              ? 'Not broadcasting'
                              : live.title ?? 'LIVE',
                          style: LR.title.copyWith(fontSize: 19),
                        ),
                      ),
                      if (session != null)
                        LrStatusChip(
                          label: live.lastPushFailed ? 'RECONNECTING' : 'LIVE',
                          color: live.lastPushFailed ? LR.inkSoft : LR.alert,
                          filled: !live.lastPushFailed,
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    session == null
                        ? 'Start a LIVE session and share one link. Anyone with '
                              'it sees your position, speed, distance and heart '
                              'rate on a full-screen map — no account needed.'
                        : 'Riding as ${services.profile.riderName}. Telemetry '
                              'is sent every ${LiveSessionController.telemetryInterval.inSeconds} '
                              'seconds while a ride is '
                              'recording.',
                    style: LR.body.copyWith(height: 1.45),
                  ),
                  if (session != null) ...[
                    const SizedBox(height: 16),
                    _copyRow('JOIN CODE', session.joinToken),
                    const SizedBox(height: 10),
                    _copyRow('SPECTATOR LINK', live.viewerUrl ?? ''),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: LrStat(
                            label: 'Speed',
                            value: Fmt.speed(metrics.speedKmh, metric: metric),
                            unit: Fmt.speedUnit(metric: metric),
                          ),
                        ),
                        Expanded(
                          child: LrStat(
                            label: 'Distance',
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
                          ? 'Waiting for the first telemetry upload…'
                          : 'Last update ${Fmt.clock(live.lastAcceptedAt!)}',
                      style: LR.fieldLabel.copyWith(fontSize: 10),
                    ),
                  ],
                  const SizedBox(height: 18),
                  if (session == null)
                    FilledButton.icon(
                      onPressed: () => _openSheet(services),
                      icon: const Icon(Icons.sensors, size: 18),
                      label: const Text('START OR JOIN LIVE'),
                    )
                  else ...[
                    FilledButton.icon(
                      onPressed: () => SharePlus.instance.share(
                        ShareParams(
                          text: live.viewerUrl ?? '',
                          subject: 'Follow my ride on Live Ride',
                        ),
                      ),
                      icon: const Icon(Icons.ios_share, size: 18),
                      label: const Text('SHARE THE LINK'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await live.stop();
                        if (mounted) setState(() {});
                      },
                      icon: const Icon(Icons.stop_circle_outlined, size: 18),
                      label: const Text('END LIVE'),
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
            const LrSectionHeader(title: 'Heart rate'),
            _heartRatePanel(services),
          ],
        );
      },
    );
  }

  Widget _heartRatePanel(AppServices services) => LrPanel(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StreamBuilder<int>(
          stream: services.heartRate.bpm,
          initialData: services.heartRate.latestBpm,
          builder: (context, snapshot) => Row(
            children: [
              const Icon(Icons.favorite, color: LR.alert, size: 26),
              const SizedBox(width: 12),
              Text(snapshot.data?.toString() ?? '--', style: LR.fieldValue(34)),
              const SizedBox(width: 6),
              Text('bpm', style: LR.fieldUnit),
              const Spacer(),
              Text(
                services.heartRate.connectedId == null
                    ? 'Not connected'
                    : 'Connected',
                style: LR.fieldLabel.copyWith(fontSize: 10),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Live Ride reads the standard Bluetooth Heart Rate service. On WHOOP, '
          'enable Broadcast Heart Rate in the WHOOP app first.',
          style: LR.body.copyWith(fontSize: 12.5, height: 1.4),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _scanning ? null : () => _scan(services),
          icon: const Icon(Icons.bluetooth_searching, size: 18),
          label: Text(_scanning ? 'SCANNING…' : 'SCAN FOR SENSORS'),
        ),
        StreamBuilder<List<HeartRateDevice>>(
          stream: services.heartRate.devices,
          builder: (context, snapshot) {
            final devices = snapshot.data ?? const <HeartRateDevice>[];
            if (devices.isEmpty) return const SizedBox.shrink();
            return Column(
              children: [
                const Divider(height: 26),
                for (final device in devices.take(12))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(
                      device.likelyHeartRate ? Icons.favorite : Icons.bluetooth,
                      color: device.likelyHeartRate ? LR.alert : LR.muted,
                      size: 20,
                    ),
                    title: Text(device.name),
                    subtitle: Text('${device.rssi} dBm'),
                    trailing: const Icon(Icons.link, size: 18),
                    onTap: () => _connect(services, device),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );

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
          tooltip: 'Copy',
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

  Future<void> _scan(AppServices services) async {
    setState(() => _scanning = true);
    try {
      await services.heartRate.startScan();
      // Bluetooth scanning is battery-hungry, so it stops on its own.
      Timer(const Duration(seconds: 20), () async {
        await services.heartRate.stopScan();
        if (mounted) setState(() => _scanning = false);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _scanning = false);
        showLrMessage(context, e.toString(), error: true);
      }
    }
  }

  Future<void> _connect(AppServices services, HeartRateDevice device) async {
    try {
      await services.heartRate.connect(device.id);
      if (mounted) {
        setState(() => _scanning = false);
        showLrMessage(context, 'Connected to ${device.name}');
      }
    } catch (e) {
      if (mounted) showLrMessage(context, e.toString(), error: true);
    }
  }
}
