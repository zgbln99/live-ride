import 'package:flutter/material.dart';

import '../core/lr_theme.dart';
import '../models/route/route_preferences.dart';
import '../widgets/lr_common.dart';

/// Preferencje trasowania: typ roweru, charakter trasy, nawierzchnia
/// i rzeczy, których chcemy unikać.
Future<RoutePreferences?> showRoutePreferencesSheet(
  BuildContext context,
  RoutePreferences current,
) => showModalBottomSheet<RoutePreferences>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.75,
    maxChildSize: 0.95,
    builder: (context, scrollController) =>
        _PreferencesSheet(current: current, scrollController: scrollController),
  ),
);

class _PreferencesSheet extends StatefulWidget {
  const _PreferencesSheet({
    required this.current,
    required this.scrollController,
  });

  final RoutePreferences current;
  final ScrollController scrollController;

  @override
  State<_PreferencesSheet> createState() => _PreferencesSheetState();
}

class _PreferencesSheetState extends State<_PreferencesSheet> {
  late RoutePreferences _value = widget.current;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: ListView(
          controller: widget.scrollController,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          children: [
            const LrSectionHeader(title: 'Rower'),
            _chips<BikeProfile>(
              values: BikeProfile.values,
              selected: _value.profile,
              label: (profile) => profile.label,
              onSelected: (profile) =>
                  setState(() => _value = _value.copyWith(profile: profile)),
            ),
            const SizedBox(height: 22),
            const LrSectionHeader(title: 'Charakter trasy'),
            _chips<RouteMood>(
              values: RouteMood.values,
              selected: _value.mood,
              label: (mood) => mood.label,
              onSelected: (mood) =>
                  setState(() => _value = _value.copyWith(mood: mood)),
            ),
            const SizedBox(height: 6),
            Text(switch (_value.mood) {
              RouteMood.fast =>
                'Najkrótszy sensowny przejazd, także głównymi drogami.',
              RouteMood.balanced => 'Kompromis między czasem a spokojem jazdy.',
              RouteMood.quiet => 'Bocznymi drogami, nawet jeśli będzie dłużej.',
            }, style: LR.body.copyWith(fontSize: 12, height: 1.35)),
            const SizedBox(height: 22),
            const LrSectionHeader(title: 'Nawierzchnia'),
            _chips<SurfacePreference>(
              values: SurfacePreference.values,
              selected: _value.surface,
              label: (surface) => surface.label,
              onSelected: (surface) =>
                  setState(() => _value = _value.copyWith(surface: surface)),
            ),
            const SizedBox(height: 22),
            const LrSectionHeader(title: 'Unikaj i preferuj'),
            LrPanel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _toggle(
                    'Preferuj ścieżki rowerowe',
                    _value.preferBikePaths,
                    (value) => _value = _value.copyWith(preferBikePaths: value),
                  ),
                  const Divider(height: 1),
                  _toggle(
                    'Unikaj ruchliwych dróg',
                    _value.avoidBusyRoads,
                    (value) => _value = _value.copyWith(avoidBusyRoads: value),
                  ),
                  const Divider(height: 1),
                  _toggle(
                    'Unikaj podjazdów',
                    _value.avoidHills,
                    (value) => _value = _value.copyWith(avoidHills: value),
                    subtitle:
                        'Router wybierze płaskszy wariant, jeśli istnieje',
                  ),
                  const Divider(height: 1),
                  _toggle(
                    'Unikaj promów',
                    _value.avoidFerries,
                    (value) => _value = _value.copyWith(avoidFerries: value),
                  ),
                  const Divider(height: 1),
                  _toggle(
                    'Unikaj dróg ekspresowych',
                    _value.avoidMotorways,
                    (value) => _value = _value.copyWith(avoidMotorways: value),
                    subtitle: 'Profil rowerowy i tak ich nie używa',
                  ),
                  const Divider(height: 1),
                  _toggle(
                    'Unikaj tuneli',
                    _value.avoidTunnels,
                    (value) => _value = _value.copyWith(avoidTunnels: value),
                    subtitle:
                        'Zapisywane przy trasie; router Valhalla nie ma '
                        'osobnego przełącznika na tunele',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Zakładana prędkość: '
              '${_value.assumedSpeedKmh.toStringAsFixed(0)} km/h — na jej '
              'podstawie liczony jest przewidywany czas.',
              style: LR.body.copyWith(fontSize: 12, height: 1.35),
            ),
          ],
        ),
      ),
      Container(
        decoration: const BoxDecoration(
          color: LR.surface,
          border: Border(top: BorderSide(color: LR.line)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            child: FilledButton(
              onPressed: () => Navigator.pop(context, _value),
              child: const Text('ZASTOSUJ'),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _chips<T>({
    required List<T> values,
    required T selected,
    required String Function(T) label,
    required void Function(T) onSelected,
  }) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final value in values)
        ChoiceChip(
          label: Text(label(value)),
          selected: selected == value,
          showCheckmark: false,
          onSelected: (_) => onSelected(value),
        ),
    ],
  );

  Widget _toggle(
    String title,
    bool value,
    RoutePreferences Function(bool) apply, {
    String? subtitle,
  }) => SwitchListTile(
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle),
    value: value,
    onChanged: (next) => setState(() => _value = apply(next)),
  );
}
