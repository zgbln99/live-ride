import 'package:flutter/material.dart';

import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../models/ride_alert.dart';
import '../services/app_services.dart';
import '../widgets/lr_common.dart';

/// Ustawienia powiadomień w czasie jazdy.
///
/// Powiadomienie, które potrzebuje sensora, da się włączyć także bez niego —
/// po prostu nigdy się nie odezwie, i ekran mówi to wprost, zamiast udawać,
/// że działa.
class AlertSettingsScreen extends StatelessWidget {
  const AlertSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    final controller = services.alerts;

    return AnimatedBuilder(
      animation: Listenable.merge([controller, services.sensors]),
      builder: (context, _) {
        final settings = controller.settings;
        final hasPower = services.sensors.connected.any(
          (device) => device.capabilities.power,
        );
        final hasCadence = services.sensors.connected.any(
          (device) => device.capabilities.cadence,
        );
        final hasHeartRate = services.heartRate.isConnected;

        String? missing(AlertKind kind) => switch (kind) {
          AlertKind.powerHigh when !hasPower => S.needsPowerMeter,
          AlertKind.cadenceLow when !hasCadence => S.needsCadenceSensor,
          AlertKind.heartRateHigh when !hasHeartRate => S.needsHeartRateStrap,
          _ => null,
        };

        return Scaffold(
          appBar: AppBar(title: Text(S.alerts)),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              SwitchListTile(
                title: Text(S.haptics),
                subtitle: Text(S.hapticsHint),
                value: controller.hapticsEnabled,
                onChanged: controller.setHaptics,
              ),
              SwitchListTile(
                title: Text(S.speech),
                subtitle: Text(S.speechHint),
                value: controller.speechEnabled,
                onChanged: controller.setSpeech,
              ),
              const Divider(height: 1),
              LrSectionHeader(title: S.alerts),
              for (final kind in AlertKind.values)
                _AlertRuleTile(
                  rule: settings.ruleFor(kind),
                  missing: missing(kind),
                  onChanged: (rule) =>
                      controller.updateSettings(settings.withRule(rule)),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _AlertRuleTile extends StatelessWidget {
  const _AlertRuleTile({
    required this.rule,
    required this.missing,
    required this.onChanged,
  });

  final AlertRule rule;
  final String? missing;
  final void Function(AlertRule rule) onChanged;

  @override
  Widget build(BuildContext context) {
    final subtitle = <String>[
      if (rule.everyMinutes != null) 'co ${rule.everyMinutes} min',
      if (rule.everyKilometers != null)
        'co ${rule.everyKilometers!.round()} km',
      if (rule.threshold != null) _thresholdLabel(),
      ?missing,
    ];

    return Column(
      children: [
        SwitchListTile(
          title: Text(rule.kind.label),
          subtitle: subtitle.isEmpty
              ? null
              : Text(
                  subtitle.join(' · '),
                  style: LR.body.copyWith(
                    fontSize: 12.5,
                    color: missing != null ? LR.alert : LR.inkSoft,
                  ),
                ),
          value: rule.enabled,
          onChanged: (value) => onChanged(rule.copyWith(enabled: value)),
        ),
        if (rule.enabled && rule.everyMinutes != null)
          _Slider(
            label: S.everyMinutes,
            value: rule.everyMinutes!.toDouble(),
            min: 5,
            max: 120,
            divisions: 23,
            suffix: 'min',
            onChanged: (value) =>
                onChanged(rule.copyWith(everyMinutes: value.round())),
          ),
        if (rule.enabled && rule.everyKilometers != null)
          _Slider(
            label: S.everyKilometers,
            value: rule.everyKilometers!,
            min: 1,
            max: 50,
            divisions: 49,
            suffix: 'km',
            onChanged: (value) => onChanged(
              rule.copyWith(everyKilometers: value.roundToDouble()),
            ),
          ),
        if (rule.enabled && rule.threshold != null)
          _Slider(
            label: S.threshold,
            value: rule.threshold!,
            min: _thresholdRange().$1,
            max: _thresholdRange().$2,
            divisions: 40,
            suffix: _thresholdUnit(),
            onChanged: (value) =>
                onChanged(rule.copyWith(threshold: value.roundToDouble())),
          ),
      ],
    );
  }

  String _thresholdLabel() => '${rule.threshold!.round()} ${_thresholdUnit()}';

  String _thresholdUnit() => switch (rule.kind) {
    AlertKind.heartRateHigh => 'bpm',
    AlertKind.powerHigh => 'W',
    AlertKind.cadenceLow => 'rpm',
    AlertKind.sensorBattery => '%',
    AlertKind.rain => '%',
    AlertKind.sunset => 'min',
    _ => '',
  };

  (double, double) _thresholdRange() => switch (rule.kind) {
    AlertKind.heartRateHigh => (120, 210),
    AlertKind.powerHigh => (100, 600),
    AlertKind.cadenceLow => (40, 100),
    AlertKind.sensorBattery => (5, 50),
    AlertKind.rain => (20, 100),
    AlertKind.sunset => (5, 120),
    _ => (0, 100),
  };
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.suffix,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String suffix;
  final void Function(double value) onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
    child: Row(
      children: [
        SizedBox(width: 90, child: Text(label, style: LR.fieldLabel)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: '${value.round()} $suffix',
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 60,
          child: Text(
            '${value.round()} $suffix',
            textAlign: TextAlign.end,
            style: LR.body.copyWith(fontSize: 12.5),
          ),
        ),
      ],
    ),
  );
}
