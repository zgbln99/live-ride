import 'package:flutter/material.dart';

import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../models/rider_profile.dart';
import '../services/app_services.dart';
import '../widgets/lr_common.dart';

/// Dane zawodnika: kim jest i czym da się liczyć strefy.
///
/// Każde pole fizjologiczne wolno zostawić puste. Puste znaczy „nie wiem",
/// a nie „zero": aplikacja wtedy po prostu nie pokazuje tego, czego bez
/// tej liczby nie da się policzyć.
class ProfileEditorScreen extends StatefulWidget {
  const ProfileEditorScreen({super.key});

  @override
  State<ProfileEditorScreen> createState() => _ProfileEditorScreenState();
}

class _ProfileEditorScreenState extends State<ProfileEditorScreen> {
  late final AppServices _services = AppServices.of(context);
  late RiderProfile _profile = _services.profile.profile;

  late final TextEditingController _name = TextEditingController(
    text: _profile.displayName,
  );
  late final TextEditingController _bio = TextEditingController(
    text: _profile.bio,
  );
  late final TextEditingController _location = TextEditingController(
    text: _profile.location,
  );
  late final TextEditingController _weight = TextEditingController(
    text: _profile.weightKg?.toStringAsFixed(1) ?? '',
  );
  late final TextEditingController _height = TextEditingController(
    text: _profile.heightCm?.toStringAsFixed(0) ?? '',
  );
  late final TextEditingController _birthYear = TextEditingController(
    text: _profile.birthYear?.toString() ?? '',
  );
  late final TextEditingController _ftp = TextEditingController(
    text: _profile.ftpWatts?.toString() ?? '',
  );
  late final TextEditingController _maxHr = TextEditingController(
    text: _profile.maxHeartRate?.toString() ?? '',
  );
  late final TextEditingController _restingHr = TextEditingController(
    text: _profile.restingHeartRate?.toString() ?? '',
  );

  @override
  void dispose() {
    for (final controller in [
      _name,
      _bio,
      _location,
      _weight,
      _height,
      _birthYear,
      _ftp,
      _maxHr,
      _restingHr,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    double? number(TextEditingController controller) =>
        double.tryParse(controller.text.trim().replaceAll(',', '.'));
    int? whole(TextEditingController controller) =>
        int.tryParse(controller.text.trim());

    final next = _profile.copyWith(
      displayName: _name.text.trim(),
      bio: _bio.text.trim(),
      location: _location.text.trim(),
      weightKg: number(_weight),
      heightCm: number(_height),
      birthYear: whole(_birthYear),
      ftpWatts: whole(_ftp),
      maxHeartRate: whole(_maxHr),
      restingHeartRate: whole(_restingHr),
    );
    await _services.profile.update(next);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final training = _services.profile.trainingProfile;

    return Scaffold(
      appBar: AppBar(
        title: Text(S.profile),
        actions: [TextButton(onPressed: _save, child: Text(S.save))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          LrSectionHeader(
            title: S.identity,
            padding: const EdgeInsets.only(bottom: 8),
          ),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: S.displayName,
              helperText: S.displayNameHint,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _location,
            decoration: InputDecoration(labelText: S.location),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _bio,
            maxLines: 3,
            maxLength: 180,
            decoration: InputDecoration(labelText: S.bio),
          ),
          const SizedBox(height: 8),
          LrSectionHeader(
            title: S.physiology,
            padding: const EdgeInsets.only(bottom: 8),
          ),
          Text(S.physiologyHint, style: LR.body.copyWith(fontSize: 12.5)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _weight,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(labelText: S.weightKg),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _height,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: S.heightCm),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _birthYear,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: S.birthYear),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ftp,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: S.ftp),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _maxHr,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: S.maxHeartRateLabel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _restingHr,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: S.restingHeartRateLabel,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (training.hasHeartRateZones || training.hasPowerZones)
            LrPanel(
              child: Row(
                children: [
                  const Icon(Icons.insights, size: 18, color: LR.accentDeep),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      S.zonesReady,
                      style: LR.body.copyWith(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            )
          else
            LrPanel(
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 18, color: LR.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      S.zonesMissing,
                      style: LR.body.copyWith(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
