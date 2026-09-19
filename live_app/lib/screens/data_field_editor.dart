import 'package:flutter/material.dart';

import '../core/lr_theme.dart';
import '../models/ride_data_field.dart';
import '../services/app_services.dart';
import '../widgets/lr_common.dart';

/// Chooses the ride computer layout and what each field shows.
///
/// A rider sets this once and it applies to free rides and navigation alike.
Future<void> showDataFieldEditor(BuildContext context, AppServices services) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      maxChildSize: 0.95,
      builder: (context, scrollController) =>
          _FieldEditor(services: services, scrollController: scrollController),
    ),
  );
}

class _FieldEditor extends StatefulWidget {
  const _FieldEditor({required this.services, required this.scrollController});

  final AppServices services;
  final ScrollController scrollController;

  @override
  State<_FieldEditor> createState() => _FieldEditorState();
}

class _FieldEditorState extends State<_FieldEditor> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final profileService = widget.services.profile;
    final profile = profileService.profile;
    final fields = profile.activeFields;
    if (_selected >= fields.length) _selected = 0;

    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: LrSectionHeader(title: 'Data fields'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              for (final layout in RideFieldLayout.values) ...[
                Expanded(
                  child: _LayoutChoice(
                    layout: layout,
                    selected: profile.layout == layout,
                    onTap: () {
                      profileService.update(profile.copyWith(layout: layout));
                      setState(() => _selected = 0);
                    },
                  ),
                ),
                if (layout != RideFieldLayout.values.last)
                  const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < fields.length; i++)
                ChoiceChip(
                  label: Text('${i + 1}. ${fields[i].label}'),
                  selected: _selected == i,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _selected = i),
                ),
            ],
          ),
        ),
        const Divider(height: 24),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            children: [
              for (final field in RideDataField.values)
                ListTile(
                  dense: true,
                  title: Text(field.label),
                  leading: Icon(
                    field == fields[_selected]
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: field == fields[_selected]
                        ? LR.accentDeep
                        : LR.muted,
                    size: 20,
                  ),
                  onTap: () {
                    final next = List<RideDataField>.of(fields);
                    next[_selected] = field;
                    profileService.update(profile.copyWith(fields: next));
                    setState(() {});
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LayoutChoice extends StatelessWidget {
  const _LayoutChoice({
    required this.layout,
    required this.selected,
    required this.onTap,
  });

  final RideFieldLayout layout;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(5),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: selected ? LR.accent.withValues(alpha: 0.14) : LR.surface,
        border: Border.all(
          color: selected ? LR.accentDeep : LR.line,
          width: selected ? 1.6 : 1,
        ),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        children: [
          _LayoutGlyph(layout: layout),
          const SizedBox(height: 8),
          Text(
            '${layout.fieldCount}',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
          ),
        ],
      ),
    ),
  );
}

class _LayoutGlyph extends StatelessWidget {
  const _LayoutGlyph({required this.layout});

  final RideFieldLayout layout;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 30,
    height: 26,
    child: Column(
      children: [
        for (var row = 0; row < layout.rows; row++)
          Expanded(
            child: Row(
              children: [
                for (var column = 0; column < layout.columns; column++)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.all(1),
                      color: LR.inkSoft,
                    ),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}
