import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../models/bike.dart';
import '../services/app_services.dart';
import '../services/local_store.dart';
import '../widgets/lr_common.dart';

/// Garaż: rowery, ich przebieg i stan komponentów.
class GarageScreen extends StatelessWidget {
  const GarageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final garage = AppServices.of(context).garage;
    final metric = AppServices.of(context).profile.profile.metricUnits;

    return AnimatedBuilder(
      animation: garage,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(S.garage)),
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: Text(S.addBike),
          onPressed: () => _editBike(context, null),
        ),
        body: garage.bikes.isEmpty
            ? LrEmptyState(
                icon: Icons.pedal_bike,
                title: S.garageEmpty,
                message: S.garageEmptyMessage,
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                children: [
                  for (final bike in garage.bikes) ...[
                    _BikeCard(bike: bike, metric: metric),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
      ),
    );
  }

  static Future<void> _editBike(BuildContext context, Bike? bike) async {
    final garage = AppServices.of(context).garage;
    final nameController = TextEditingController(text: bike?.name ?? '');
    final weightController = TextEditingController(
      text: bike?.weightKg?.toStringAsFixed(1) ?? '',
    );
    var kind = bike?.kind ?? BikeKind.road;
    var isDefault = bike?.isDefault ?? garage.bikes.isEmpty;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LrSectionHeader(title: bike == null ? S.addBike : S.edit),
                  TextField(
                    controller: nameController,
                    autofocus: bike == null,
                    decoration: InputDecoration(labelText: S.bikeName),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<BikeKind>(
                    initialValue: kind,
                    decoration: InputDecoration(labelText: S.bikeKind),
                    items: [
                      for (final value in BikeKind.values)
                        DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                    ],
                    onChanged: (value) =>
                        setSheetState(() => kind = value ?? kind),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: weightController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(labelText: S.bikeWeight),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(S.defaultBike),
                    value: isDefault,
                    onChanged: (value) =>
                        setSheetState(() => isDefault = value),
                  ),
                  const SizedBox(height: 4),
                  FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(true),
                    child: Text(S.save),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final name = nameController.text.trim();
    nameController.dispose();
    final weight = double.tryParse(
      weightController.text.trim().replaceAll(',', '.'),
    );
    weightController.dispose();
    if (saved != true || name.isEmpty) return;

    await garage.saveBike(
      Bike(
        id: bike?.id ?? newLocalId('bike'),
        name: name,
        kind: kind,
        createdAt: bike?.createdAt ?? DateTime.now(),
        weightKg: weight,
        wheelCircumferenceMm: bike?.wheelCircumferenceMm,
        photoPath: bike?.photoPath,
        odometerMeters: bike?.odometerMeters ?? 0,
        isDefault: isDefault,
      ),
    );
  }
}

class _BikeCard extends StatelessWidget {
  const _BikeCard({required this.bike, required this.metric});

  final Bike bike;
  final bool metric;

  @override
  Widget build(BuildContext context) {
    final garage = AppServices.of(context).garage;
    final components = garage.componentsOf(bike.id);
    final now = DateTime.now();

    return LrPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.pedal_bike),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    bike.name,
                    overflow: TextOverflow.ellipsis,
                    style: LR.fieldValue(17),
                  ),
                ),
                if (bike.isDefault) ...[
                  const SizedBox(width: 8),
                  LrStatusChip(label: S.defaultShort, color: LR.accentDeep),
                ],
              ],
            ),
            subtitle: Text(
              '${bike.kind.label} · '
              '${Fmt.distance(bike.odometerMeters, metric: metric)} '
              '${Fmt.distanceUnit(metric: metric)}'
              '${bike.weightKg == null ? '' : ' · ${bike.weightKg} kg'}',
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) async {
                switch (value) {
                  case 'edit':
                    await GarageScreen._editBike(context, bike);
                  case 'odometer':
                    if (context.mounted) await _editOdometer(context);
                  case 'component':
                    if (context.mounted) await _addComponent(context);
                  case 'delete':
                    await garage.deleteBike(bike.id);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'edit', child: Text(S.edit)),
                PopupMenuItem(value: 'odometer', child: Text(S.setOdometer)),
                PopupMenuItem(value: 'component', child: Text(S.addComponent)),
                PopupMenuItem(value: 'delete', child: Text(S.delete)),
              ],
            ),
          ),
          if (components.isNotEmpty) const Divider(height: 1),
          for (final component in components)
            _ComponentTile(
              bike: bike,
              component: component,
              now: now,
              metric: metric,
            ),
        ],
      ),
    );
  }

  Future<void> _editOdometer(BuildContext context) async {
    final garage = AppServices.of(context).garage;
    final controller = TextEditingController(
      text: bike.odometerKilometers.toStringAsFixed(0),
    );
    final value = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.setOdometer),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'km'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              double.tryParse(controller.text.trim().replaceAll(',', '.')),
            ),
            child: Text(S.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value < 0) return;
    await garage.setOdometer(bike.id, value * 1000);
  }

  Future<void> _addComponent(BuildContext context) async {
    final garage = AppServices.of(context).garage;
    var kind = ComponentKind.chain;
    final limitController = TextEditingController(
      text: '${ComponentKind.chain.defaultLimitKm ?? ''}',
    );

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LrSectionHeader(title: S.addComponent),
                  DropdownButtonFormField<ComponentKind>(
                    initialValue: kind,
                    decoration: InputDecoration(labelText: S.component),
                    items: [
                      for (final value in ComponentKind.values)
                        DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                    ],
                    onChanged: (value) => setSheetState(() {
                      kind = value ?? kind;
                      limitController.text = '${kind.defaultLimitKm ?? ''}';
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: limitController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: S.serviceLimit,
                      helperText: S.serviceLimitHint,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(true),
                    child: Text(S.save),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final limitKm = double.tryParse(limitController.text.trim());
    limitController.dispose();
    if (saved != true) return;

    await garage.saveComponent(
      BikeComponent(
        id: newLocalId('component'),
        bikeId: bike.id,
        name: kind.label,
        kind: kind,
        installedAt: DateTime.now(),
        odometerAtInstallMeters: bike.odometerMeters,
        limitMeters: limitKm == null ? null : limitKm * 1000,
        limitDays: kind.defaultLimitDays,
      ),
    );
  }
}

class _ComponentTile extends StatelessWidget {
  const _ComponentTile({
    required this.bike,
    required this.component,
    required this.now,
    required this.metric,
  });

  final Bike bike;
  final BikeComponent component;
  final DateTime now;
  final bool metric;

  @override
  Widget build(BuildContext context) {
    final garage = AppServices.of(context).garage;
    final wear = component.wear(bike.odometerMeters, now);
    final due = component.isDue(bike.odometerMeters, now);
    final soon = component.isSoon(bike.odometerMeters, now);
    final color = due ? LR.alert : (soon ? const Color(0xFFE07A1F) : LR.go);

    return ListTile(
      dense: true,
      title: Text(component.name, style: LR.fieldValue(14)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            [
              '${Fmt.distance(component.usedMeters(bike.odometerMeters), metric: metric)} '
                  '${Fmt.distanceUnit(metric: metric)}',
              if (component.limitMeters != null)
                'z ${Fmt.distance(component.limitMeters!, metric: metric)} '
                    '${Fmt.distanceUnit(metric: metric)}',
              if (component.limitDays != null)
                '${component.usedDays(now)}/${component.limitDays} dni',
            ].join(' '),
            style: LR.body.copyWith(fontSize: 11.5),
          ),
          const SizedBox(height: 5),
          if (wear != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: wear.clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: LR.line,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            )
          else
            Text(S.noServiceLimit, style: LR.body.copyWith(fontSize: 11)),
        ],
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) async {
          if (value == 'reset') await garage.resetComponent(component);
          if (value == 'delete') await garage.deleteComponent(component.id);
        },
        itemBuilder: (context) => [
          PopupMenuItem(value: 'reset', child: Text(S.replacedComponent)),
          PopupMenuItem(value: 'delete', child: Text(S.delete)),
        ],
      ),
    );
  }
}
