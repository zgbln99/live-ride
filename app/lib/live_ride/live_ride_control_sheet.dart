import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wanderer/heart_rate/ble_heart_rate_source.dart';
import 'package:wanderer/live_ride/live_ride_coordinator.dart';

Future<void> showLiveRideControlSheet(
  BuildContext context, {
  required LiveRideCoordinator coordinator,
  required BleHeartRateSource heartRate,
  String? trailId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => LiveRideControlSheet(
      coordinator: coordinator,
      heartRate: heartRate,
      trailId: trailId,
    ),
  );
}

class LiveRideControlSheet extends StatefulWidget {
  const LiveRideControlSheet({
    super.key,
    required this.coordinator,
    required this.heartRate,
    this.trailId,
  });

  final LiveRideCoordinator coordinator;
  final BleHeartRateSource heartRate;
  final String? trailId;

  @override
  State<LiveRideControlSheet> createState() => _LiveRideControlSheetState();
}

class _LiveRideControlSheetState extends State<LiveRideControlSheet> {
  final _title = TextEditingController(text: 'Live Ride');
  final _joinCode = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _joinCode.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.coordinator.session;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Live Ride', style: theme.textTheme.headlineSmall),
                ),
                if (session != null)
                  const Chip(
                    avatar: Icon(Icons.circle, size: 10, color: Colors.red),
                    label: Text('LIVE'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _HeartRateCard(heartRate: widget.heartRate),
            const SizedBox(height: 18),
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              const SizedBox(height: 12),
            ],
            if (session == null) ...[
              TextField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: 'Ride name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        await widget.coordinator.create(
                          title: _title.text.trim().isEmpty
                              ? 'Live Ride'
                              : _title.text.trim(),
                          trailId: widget.trailId,
                        );
                      }),
                icon: const Icon(Icons.sensors),
                label: const Text('Start Live Ride'),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or join'),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
              ),
              TextField(
                controller: _joinCode,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Join code',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy || _joinCode.text.trim().isEmpty
                    ? null
                    : () => _run(() async {
                        await widget.coordinator.join(_joinCode.text.trim());
                      }),
                icon: const Icon(Icons.group_add),
                label: const Text('Join Live Ride'),
              ),
            ] else ...[
              _CopyRow(
                label: 'Spectator link',
                value: widget.coordinator.api.viewerUrl(session.shareToken),
              ),
              const SizedBox(height: 10),
              _CopyRow(label: 'Join code', value: session.joinToken),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        await widget.coordinator.leave(
                          endForEveryone: widget.coordinator.isOwner,
                        );
                      }),
                icon: const Icon(Icons.stop_circle_outlined),
                label: Text(
                  widget.coordinator.isOwner
                      ? 'End Live Ride for everyone'
                      : 'Leave Live Ride',
                ),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      child: Row(
        children: [
          Expanded(
            child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            tooltip: 'Copy',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$label copied')),
                );
              }
            },
            icon: const Icon(Icons.copy),
          ),
        ],
      ),
    );
  }
}

class _HeartRateCard extends StatefulWidget {
  const _HeartRateCard({required this.heartRate});

  final BleHeartRateSource heartRate;

  @override
  State<_HeartRateCard> createState() => _HeartRateCardState();
}

class _HeartRateCardState extends State<_HeartRateCard> {
  StreamSubscription<int>? _sub;
  int? _bpm;

  @override
  void initState() {
    super.initState();
    _bpm = widget.heartRate.latestBpm;
    _sub = widget.heartRate.bpm.listen((bpm) {
      if (mounted) setState(() => _bpm = bpm);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.favorite, color: Colors.redAccent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Heart rate sensor'),
                  Text(
                    _bpm == null ? 'Not connected' : '$_bpm bpm',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _showHeartRateDevices(context, widget.heartRate),
              child: Text(_bpm == null ? 'Connect' : 'Change'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showHeartRateDevices(
  BuildContext context,
  BleHeartRateSource heartRate,
) async {
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (sheetContext) => _HeartRateDevicePicker(heartRate: heartRate),
  );
}

class _HeartRateDevicePicker extends StatefulWidget {
  const _HeartRateDevicePicker({required this.heartRate});

  final BleHeartRateSource heartRate;

  @override
  State<_HeartRateDevicePicker> createState() => _HeartRateDevicePickerState();
}

class _HeartRateDevicePickerState extends State<_HeartRateDevicePicker> {
  String? _error;
  String? _connecting;

  @override
  void initState() {
    super.initState();
    unawaited(_scan());
  }

  Future<void> _scan() async {
    try {
      await widget.heartRate.startScan();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    unawaited(widget.heartRate.stopScan());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Heart rate sensors', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text('Enable HR broadcast on WHOOP, then choose your device.'),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: StreamBuilder<List<BleHeartRateDevice>>(
              stream: widget.heartRate.devices,
              initialData: const [],
              builder: (context, snapshot) {
                final devices = snapshot.data ?? const [];
                if (devices.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: devices.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    return ListTile(
                      leading: const Icon(Icons.monitor_heart_outlined),
                      title: Text(device.name),
                      subtitle: Text('${device.rssi} dBm'),
                      trailing: _connecting == device.id
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chevron_right),
                      onTap: _connecting != null
                          ? null
                          : () async {
                              setState(() => _connecting = device.id);
                              try {
                                await widget.heartRate.connect(device.id);
                                if (context.mounted) Navigator.pop(context);
                              } catch (e) {
                                if (mounted) {
                                  setState(() {
                                    _connecting = null;
                                    _error = e.toString();
                                  });
                                }
                              }
                            },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
