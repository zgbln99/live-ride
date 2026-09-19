import 'dart:async';

import 'package:flutter/material.dart';

import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../models/sensor_device.dart';
import '../services/app_services.dart';
import '../services/sensor_hub.dart';
import '../widgets/lr_common.dart';
import 'whoop_screen.dart';

/// Sensory rowerowe: kadencja, prędkość, moc, trenażer.
///
/// Pasek na klatę ma własny ekran ([WhoopScreen]), bo sposób łączenia z nim
/// — zwłaszcza z WHOOP — jest na tyle inny, że mieszanie tego w jedną listę
/// utrudniałoby obie rzeczy.
class SensorsScreen extends StatefulWidget {
  const SensorsScreen({super.key});

  @override
  State<SensorsScreen> createState() => _SensorsScreenState();
}

class _SensorsScreenState extends State<SensorsScreen> {
  String? _error;
  String? _busyId;

  SensorHub get _hub => AppServices.of(context).sensors;

  /// Zapamiętany w [didChangeDependencies], bo w [dispose] kontekst już nie
  /// pozwala sięgnąć po serwisy.
  late SensorHub _hubForDispose;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _hubForDispose = AppServices.of(context).sensors;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  @override
  void dispose() {
    unawaited(_hubForDispose.stopScan());
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() => _error = null);
    try {
      await _hub.startScan();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is StateError ? e.message : e.toString());
      }
    }
  }

  Future<void> _connect(SensorDevice device) async {
    setState(() {
      _busyId = device.id;
      _error = null;
    });
    try {
      await _hub.connect(device.id);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is StateError ? e.message : e.toString());
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hub = _hub;
    return AnimatedBuilder(
      animation: hub,
      builder: (context, _) {
        final snapshot = hub.snapshot;
        return Scaffold(
          appBar: AppBar(
            title: Text(S.sensors),
            actions: [
              IconButton(
                tooltip: S.search,
                icon: hub.isScanning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                onPressed: hub.isScanning ? null : _scan,
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _LiveValues(snapshot: snapshot),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: LrPanel(
                    borderColor: LR.alert,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: LR.alert,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _error!,
                            style: LR.body.copyWith(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              LrSectionHeader(title: S.heartRate),
              ListTile(
                leading: const Icon(Icons.favorite, color: LR.alert),
                title: Text(
                  AppServices.of(context).heartRate.connectedName ??
                      S.heartRateStrap,
                ),
                subtitle: Text(
                  AppServices.of(context).heartRate.isConnected
                      ? SensorStatus.streaming.label
                      : SensorStatus.idle.label,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const WhoopScreen()),
                ),
              ),
              if (hub.paired.isNotEmpty) ...[
                LrSectionHeader(title: S.pairedSensors),
                for (final device in hub.paired)
                  _SensorTile(
                    device: device,
                    connected: hub.isConnectedTo(device.id),
                    busy: _busyId == device.id,
                    onConnect: () => _connect(device),
                    onDisconnect: () => hub.disconnect(device.id),
                    onForget: () => hub.forget(device.id),
                    onAutoConnect: (value) =>
                        hub.setAutoConnect(device.id, value),
                  ),
              ],
              LrSectionHeader(title: S.foundSensors),
              if (hub.discovered.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    hub.isScanning ? S.searchingSensors : S.noSensorsFound,
                    style: LR.body,
                  ),
                )
              else
                for (final device in hub.discovered)
                  _SensorTile(
                    device: device,
                    connected: false,
                    busy: _busyId == device.id,
                    onConnect: () => _connect(device),
                  ),
              LrSectionHeader(title: S.sensorSources),
              _SourceControls(hub: hub),
            ],
          ),
        );
      },
    );
  }
}

class _LiveValues extends StatelessWidget {
  const _LiveValues({required this.snapshot});

  final SensorSnapshot snapshot;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
    child: LrPanel(
      child: Row(
        children: [
          Expanded(
            child: LrStat(
              label: S.heartRate,
              value: snapshot.heartRateBpm?.toString() ?? S.notAvailable,
              unit: 'bpm',
              valueSize: 24,
            ),
          ),
          Expanded(
            child: LrStat(
              label: S.cadence,
              value: snapshot.cadenceRpm?.round().toString() ?? S.notAvailable,
              unit: 'rpm',
              valueSize: 24,
            ),
          ),
          Expanded(
            child: LrStat(
              label: S.power,
              value: snapshot.powerWatts?.toString() ?? S.notAvailable,
              unit: 'W',
              valueSize: 24,
            ),
          ),
        ],
      ),
    ),
  );
}

class _SensorTile extends StatelessWidget {
  const _SensorTile({
    required this.device,
    required this.connected,
    required this.busy,
    required this.onConnect,
    this.onDisconnect,
    this.onForget,
    this.onAutoConnect,
  });

  final SensorDevice device;
  final bool connected;
  final bool busy;
  final VoidCallback onConnect;
  final VoidCallback? onDisconnect;
  final VoidCallback? onForget;
  final void Function(bool value)? onAutoConnect;

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      device.kind.label,
      if (device.batteryPercent != null) '${device.batteryPercent} %',
      if (device.rssi != null) '${device.signalBars}/4',
      if (connected && device.isStale) S.sensorStale,
    ];

    return ListTile(
      leading: Icon(switch (device.kind) {
        SensorKind.power => Icons.bolt,
        SensorKind.cadence => Icons.rotate_right,
        SensorKind.speed => Icons.speed,
        SensorKind.speedAndCadence => Icons.speed,
        SensorKind.trainer => Icons.fitness_center,
        SensorKind.heartRate => Icons.favorite,
        SensorKind.unknown => Icons.bluetooth,
      }, color: connected ? LR.go : LR.muted),
      title: Text(device.name),
      subtitle: Text(details.join(' · ')),
      trailing: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : connected
          ? PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'disconnect') onDisconnect?.call();
                if (value == 'forget') onForget?.call();
                if (value == 'auto') {
                  onAutoConnect?.call(!device.autoConnect);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'auto',
                  child: Text(
                    device.autoConnect ? S.autoConnectOff : S.autoConnectOn,
                  ),
                ),
                PopupMenuItem(value: 'disconnect', child: Text(S.disconnect)),
                PopupMenuItem(value: 'forget', child: Text(S.forgetSensor)),
              ],
            )
          : TextButton(onPressed: onConnect, child: Text(S.connect)),
    );
  }
}

class _SourceControls extends StatelessWidget {
  const _SourceControls({required this.hub});

  final SensorHub hub;

  @override
  Widget build(BuildContext context) {
    final sources = hub.sources;
    return Column(
      children: [
        ListTile(
          title: Text(S.speedSource),
          subtitle: Text('${sources.speed.label} · ${S.speedSourceHint}'),
          trailing: DropdownButton<MetricSource>(
            value: sources.speed,
            underline: const SizedBox.shrink(),
            items: [
              for (final source in MetricSource.values)
                DropdownMenuItem(value: source, child: Text(source.label)),
            ],
            onChanged: (value) => value == null
                ? null
                : hub.updateSources(sources.copyWith(speed: value)),
          ),
        ),
        ListTile(
          title: Text(S.wheelCircumference),
          subtitle: Text('${sources.wheelCircumferenceMm.round()} mm'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _editCircumference(context),
        ),
      ],
    );
  }

  Future<void> _editCircumference(BuildContext context) async {
    final controller = TextEditingController(
      text: hub.sources.wheelCircumferenceMm.round().toString(),
    );
    final value = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.wheelCircumference),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'mm',
            helperText: S.wheelCircumferenceHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              double.tryParse(controller.text.trim()),
            ),
            child: Text(S.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value < 800 || value > 3000) return;
    await hub.updateSources(hub.sources.copyWith(wheelCircumferenceMm: value));
  }
}
