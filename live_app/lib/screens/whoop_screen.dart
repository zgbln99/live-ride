import 'dart:async';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart'
    show BluetoothLowEnergyState;
import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../services/app_services.dart';
import '../services/heart_rate_service.dart';
import '../widgets/bpm_trace.dart';
import '../widgets/lr_common.dart';

/// WHOOP and Bluetooth heart-rate setup.
///
/// This is the screen a rider opens when the number is missing, so it answers
/// the question it was opened with: is the strap connected, is it being worn,
/// how strong is the link, and what exactly do I press on WHOOP to fix it.
class WhoopScreen extends StatefulWidget {
  const WhoopScreen({super.key});

  @override
  State<WhoopScreen> createState() => _WhoopScreenState();
}

class _WhoopScreenState extends State<WhoopScreen> {
  late final HeartRateService _hr = AppServices.of(context).heartRate;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Opening this screen is a request to find the strap.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hr.isConnected && !_hr.isBusy) unawaited(_scan());
    });
  }

  @override
  void dispose() {
    unawaited(_hr.stopScan());
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() => _error = null);
    try {
      await _hr.startScan();
    } catch (e, stack) {
      debugPrint('Live Ride: czujnik tętna: $e\n$stack');
      if (mounted) {
        setState(
          () => _error = e is StateError ? e.message : S.somethingWentWrong,
        );
      }
    }
  }

  Future<void> _connect(HeartRateDevice device) async {
    setState(() => _error = null);
    try {
      await _hr.connect(device.id);
      if (mounted) showLrMessage(context, S.connectedTo(device.name));
    } catch (e, stack) {
      debugPrint('Live Ride: czujnik tętna: $e\n$stack');
      if (mounted) {
        setState(
          () => _error = e is StateError ? e.message : S.somethingWentWrong,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(S.heartRate),
      actions: [
        AnimatedBuilder(
          animation: _hr,
          builder: (context, _) => TextButton(
            onPressed: _hr.status == HeartRateStatus.scanning ? null : _scan,
            child: Text(
              _hr.status == HeartRateStatus.scanning ? S.scanning : S.scan,
            ),
          ),
        ),
      ],
    ),
    body: AnimatedBuilder(
      animation: _hr,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _statusPanel(),
          if (_error != null || _hr.lastError != null) ...[
            const SizedBox(height: 12),
            _errorPanel(_error ?? _hr.lastError!),
          ],
          if (_hr.adapterState == BluetoothLowEnergyState.poweredOff) ...[
            const SizedBox(height: 12),
            _errorPanel(S.bluetoothOff),
          ],
          const SizedBox(height: 24),
          if (!_hr.isConnected) ...[
            LrSectionHeader(title: S.usingWhoop),
            _whoopSteps(),
            const SizedBox(height: 24),
          ],
          LrSectionHeader(
            title: S.sensorsNearby,
            trailing: _hr.status == HeartRateStatus.scanning
                ? const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
          _deviceList(),
        ],
      ),
    ),
  );

  Widget _statusPanel() {
    final connected = _hr.isConnected;
    final bpm = _hr.latestBpm;
    final worn = _hr.sensorContact;

    return LrPanel(
      padding: EdgeInsets.zero,
      accentEdge: connected,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
            child: Row(
              children: [
                _statusChip(),
                const Spacer(),
                if (_hr.batteryPercent != null) ...[
                  Icon(
                    _hr.batteryPercent! <= 15
                        ? Icons.battery_alert
                        : Icons.battery_full,
                    size: 15,
                    color: _hr.batteryPercent! <= 15 ? LR.alert : LR.inkSoft,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${_hr.batteryPercent}%',
                    style: LR.fieldLabel.copyWith(fontSize: 10.5),
                  ),
                  const SizedBox(width: 12),
                ],
                if (_hr.rssi != null) ...[
                  SignalBars(
                    bars: HeartRateDevice(
                      id: '',
                      name: '',
                      rssi: _hr.rssi!,
                      advertisesHeartRate: false,
                      isWhoop: false,
                    ).signalBars,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${_hr.rssi} dBm',
                    style: LR.fieldLabel.copyWith(fontSize: 10.5),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Icon(
                  Icons.favorite,
                  size: 30,
                  color: bpm == null ? LR.lineStrong : LR.alert,
                ),
                const SizedBox(width: 14),
                Text(bpm?.toString() ?? '--', style: LR.fieldValue(64)),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text('bpm', style: LR.fieldUnit),
                ),
                const Spacer(),
                if (connected && _hr.lastSampleAt != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      _hr.isStale
                          ? S.noBeat
                          : 'UPDATED ${Fmt.clock(_hr.lastSampleAt!)}',
                      style: LR.fieldLabel.copyWith(
                        fontSize: 9.5,
                        color: _hr.isStale ? LR.alert : LR.muted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: BpmTrace(samples: _hr.history),
          ),
          if (connected) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _hr.connectedName ?? S.heartRateStrap,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          worn == null
                              ? S.connected
                              : worn
                              ? 'Worn · skin contact detected'
                              : 'Not being worn · no skin contact',
                          style: LR.body.copyWith(
                            fontSize: 12,
                            color: worn == false ? LR.alert : LR.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => unawaited(_hr.disconnect()),
                    child: Text(S.disconnect),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (_) => unawaited(_hr.forget()),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'forget',
                        child: Text(S.forgetSensor),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else if (_hr.rememberedName != null) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
              child: Row(
                children: [
                  const Icon(Icons.history, size: 17, color: LR.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Last used: ${_hr.rememberedName}',
                      style: LR.body.copyWith(fontSize: 12.5),
                    ),
                  ),
                  TextButton(
                    onPressed: _hr.isBusy
                        ? null
                        : () => unawaited(_hr.reconnectRemembered()),
                    child: Text(S.reconnect),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusChip() {
    final (label, color, filled) = switch (_hr.status) {
      HeartRateStatus.streaming =>
        _hr.isStale ? (S.noBeat, LR.inkSoft, false) : (S.live, LR.alert, true),
      HeartRateStatus.waiting => (S.connected, LR.accentDeep, false),
      HeartRateStatus.connecting => (S.connecting, LR.accentDeep, false),
      HeartRateStatus.reconnecting => (S.reconnecting, LR.alert, false),
      HeartRateStatus.scanning => (S.scanning, LR.accentDeep, false),
      HeartRateStatus.idle => (S.notConnected, LR.muted, false),
    };
    return LrStatusChip(label: label, color: color, filled: filled);
  }

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

  Widget _whoopSteps() => LrPanel(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(S.whoopIntro, style: LR.body.copyWith(height: 1.45, fontSize: 13)),
        const SizedBox(height: 16),
        _step(1, S.whoopStep1),
        _step(2, S.whoopStep2),
        _step(3, S.whoopStep3),
        _step(4, S.whoopStep4),
        const SizedBox(height: 6),
        Text(
          S.anyStrapWorks,
          style: LR.body.copyWith(fontSize: 12, height: 1.4),
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

  Widget _deviceList() {
    final devices = _hr.devices;
    if (devices.isEmpty) {
      return LrPanel(
        padding: const EdgeInsets.all(18),
        child: Text(
          _hr.status == HeartRateStatus.scanning
              ? S.lookingForSensors
              : S.noSensorsFound,
          style: LR.body,
        ),
      );
    }

    return Column(
      children: [
        for (final device in devices) ...[
          LrPanel(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            onTap: _hr.isBusy ? null : () => unawaited(_connect(device)),
            child: Row(
              children: [
                Icon(
                  device.likelyHeartRate ? Icons.favorite : Icons.bluetooth,
                  size: 19,
                  color: device.likelyHeartRate ? LR.alert : LR.muted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              device.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (device.isWhoop) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: LR.accent.withValues(alpha: 0.18),
                                border: Border.all(color: LR.accentDeep),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text(
                                'WHOOP',
                                style: TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                  color: LR.accentDeep,
                                ),
                              ),
                            ),
                          ],
                          if (device.id == _hr.connectedId) ...[
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.check_circle,
                              size: 15,
                              color: LR.go,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        device.advertisesHeartRate
                            ? S.heartRateServiceLabel
                            : device.isWhoop
                            ? 'Tap to connect · needs Broadcast Heart Rate'
                            : S.bluetoothDevice,
                        style: LR.body.copyWith(fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                SignalBars(bars: device.signalBars),
                const SizedBox(width: 10),
                const Icon(Icons.chevron_right, size: 18, color: LR.muted),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
