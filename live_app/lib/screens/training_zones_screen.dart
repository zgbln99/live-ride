import 'package:flutter/material.dart';

import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../models/training.dart';
import '../services/app_services.dart';
import '../widgets/lr_common.dart';
import 'profile_editor_screen.dart';

/// Strefy tętna i mocy zawodnika.
///
/// Ekran nic nie wymyśla: bez HR max nie ma stref tętna, bez FTP nie ma
/// stref mocy, i mówi wprost, czego brakuje.
class TrainingZonesScreen extends StatelessWidget {
  const TrainingZonesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);

    return AnimatedBuilder(
      animation: services.profile,
      builder: (context, _) {
        final training = services.profile.trainingProfile;
        final profile = services.profile.profile;
        final perKilogram = profile.wattsPerKilogram;

        return Scaffold(
          appBar: AppBar(
            title: Text(S.trainingZones),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: S.edit,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ProfileEditorScreen(),
                  ),
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              LrSectionHeader(
                title: S.heartRateZonesTitle,
                padding: const EdgeInsets.only(bottom: 8),
              ),
              if (!training.hasHeartRateZones)
                LrPanel(
                  child: Text(
                    S.zonesMissing,
                    style: LR.body.copyWith(fontSize: 13),
                  ),
                )
              else ...[
                Text(
                  training.restingHeartRate != null
                      ? S.zonesFromKarvonen
                      : S.zonesFromMaxHr,
                  style: LR.body.copyWith(fontSize: 12),
                ),
                const SizedBox(height: 8),
                _ZoneList(zones: training.heartRateZones, unit: 'bpm'),
              ],
              const SizedBox(height: 22),
              LrSectionHeader(
                title: S.powerZonesTitle,
                padding: const EdgeInsets.only(bottom: 8),
              ),
              if (!training.hasPowerZones)
                LrPanel(
                  child: Text(
                    S.zonesMissing,
                    style: LR.body.copyWith(fontSize: 13),
                  ),
                )
              else ...[
                Text(S.zonesFromFtp, style: LR.body.copyWith(fontSize: 12)),
                if (perKilogram != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${S.wattsPerKg}: ${perKilogram.toStringAsFixed(2)} W/kg',
                    style: LR.fieldValue(15),
                  ),
                ],
                const SizedBox(height: 8),
                _ZoneList(zones: training.powerZones, unit: 'W'),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ZoneList extends StatelessWidget {
  const _ZoneList({required this.zones, required this.unit});

  final List<TrainingZone> zones;
  final String unit;

  @override
  Widget build(BuildContext context) {
    // Kolory od zimnego do gorącego — te same, których używa cały rower.
    const palette = [
      Color(0xFF7C8A95),
      Color(0xFF00A868),
      Color(0xFF00BFD8),
      Color(0xFFE0A81F),
      Color(0xFFE07A1F),
      Color(0xFFE02B20),
      Color(0xFF8B1A8B),
    ];

    return LrPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < zones.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              dense: true,
              leading: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette[i % palette.length].withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Z${zones[i].index}',
                  style: LR
                      .fieldValue(13)
                      .copyWith(color: palette[i % palette.length]),
                ),
              ),
              title: Text(zones[i].name, style: LR.fieldValue(14)),
              trailing: Text(
                '${zones[i].range} $unit',
                style: LR.body.copyWith(fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
