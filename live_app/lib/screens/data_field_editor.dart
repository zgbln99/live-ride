import 'package:flutter/material.dart';

import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../models/ride_data_field.dart';
import '../models/ride_pages.dart';
import '../models/rider_profile.dart';
import '../services/app_services.dart';
import '../widgets/lr_common.dart';

/// Edytor stron komputera rowerowego.
///
/// Zawodnik ustawia to raz i obowiązuje na wolnej jeździe i na nawigacji.
/// Stron może być dowolnie wiele; każda ma swój układ i swój zestaw pól.
Future<void> showDataFieldEditor(BuildContext context, AppServices services) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      maxChildSize: 0.95,
      builder: (context, scrollController) =>
          _PageEditor(services: services, scrollController: scrollController),
    ),
  );
}

/// Wybór jednego pola — używany przy przytrzymaniu pola na ekranie jazdy.
Future<RideDataField?> showFieldPicker(
  BuildContext context,
  RiderProfile profile,
) {
  return showModalBottomSheet<RideDataField>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scrollController) => _FieldList(
        scrollController: scrollController,
        selected: null,
        onPick: (field) => Navigator.of(sheetContext).pop(field),
      ),
    ),
  );
}

class _PageEditor extends StatefulWidget {
  const _PageEditor({required this.services, required this.scrollController});

  final AppServices services;
  final ScrollController scrollController;

  @override
  State<_PageEditor> createState() => _PageEditorState();
}

class _PageEditorState extends State<_PageEditor> {
  int _page = 0;
  int _slot = 0;

  List<RideDataPage> get _pages => widget.services.profile.profile.ridePages;

  Future<void> _save(List<RideDataPage> pages) async {
    final profileService = widget.services.profile;
    await profileService.update(
      profileService.profile.copyWith(
        pages: pages,
        // Stare pola trzymamy zgodne z pierwszą stroną, żeby cokolwiek, co
        // ich jeszcze używa, pokazywało to samo.
        layout: pages.first.layout,
        fields: pages.first.activeFields,
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    if (_page >= pages.length) _page = pages.length - 1;
    final page = pages[_page];
    final fields = page.activeFields;
    if (_slot >= fields.length) _slot = 0;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: LrSectionHeader(
            title: S.dataFields,
            trailing: TextButton.icon(
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: Text(S.presets),
              onPressed: _choosePreset,
            ),
          ),
        ),
        _PageTabs(
          pages: pages,
          index: _page,
          onSelect: (index) => setState(() {
            _page = index;
            _slot = 0;
          }),
          onAdd: pages.length >= 8 ? null : _addPage,
          onRemove: pages.length <= 1 ? null : () => _removePage(_page),
          onRename: () => _renamePage(_page),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              for (final layout in RideFieldLayout.values) ...[
                Expanded(
                  child: _LayoutChoice(
                    layout: layout,
                    selected: page.layout == layout,
                    onTap: () {
                      final next = List<RideDataPage>.of(pages);
                      next[_page] = page.copyWith(layout: layout);
                      _slot = 0;
                      _save(next);
                    },
                  ),
                ),
                if (layout != RideFieldLayout.values.last)
                  const SizedBox(width: 6),
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
                  selected: _slot == i,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _slot = i),
                ),
            ],
          ),
        ),
        const Divider(height: 24),
        Expanded(
          child: _FieldList(
            scrollController: widget.scrollController,
            selected: fields[_slot],
            onPick: (field) {
              final next = List<RideDataPage>.of(pages);
              next[_page] = page.withFieldAt(_slot, field);
              _save(next);
            },
          ),
        ),
      ],
    );
  }

  Future<void> _addPage() async {
    final pages = List<RideDataPage>.of(_pages)
      ..add(
        RideDataPage(
          name: '${S.page} ${_pages.length + 1}',
          layout: RideFieldLayout.four,
          fields: const [
            RideDataField.speed,
            RideDataField.distance,
            RideDataField.elapsed,
            RideDataField.heartRate,
          ],
        ),
      );
    setState(() => _page = pages.length - 1);
    await _save(pages);
  }

  Future<void> _removePage(int index) async {
    final pages = List<RideDataPage>.of(_pages)..removeAt(index);
    setState(() => _page = 0);
    await _save(pages);
  }

  Future<void> _renamePage(int index) async {
    final controller = TextEditingController(text: _pages[index].name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.rename),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: S.page),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(S.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    final pages = List<RideDataPage>.of(_pages);
    pages[index] = pages[index].copyWith(name: name.trim());
    await _save(pages);
  }

  Future<void> _choosePreset() async {
    final preset = await showModalBottomSheet<RidePagePreset>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: LrSectionHeader(title: S.presets),
            ),
            for (final preset in RidePagePreset.values)
              ListTile(
                title: Text(preset.label),
                subtitle: Text(
                  preset.pages.map((page) => page.name).join(' · '),
                ),
                onTap: () => Navigator.of(sheetContext).pop(preset),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (preset == null) return;
    setState(() => _page = 0);
    await _save(preset.pages);
  }
}

class _PageTabs extends StatelessWidget {
  const _PageTabs({
    required this.pages,
    required this.index,
    required this.onSelect,
    required this.onAdd,
    required this.onRemove,
    required this.onRename,
  });

  final List<RideDataPage> pages;
  final int index;
  final void Function(int index) onSelect;
  final VoidCallback? onAdd;
  final VoidCallback? onRemove;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 40,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        for (var i = 0; i < pages.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(pages[i].name),
              selected: i == index,
              showCheckmark: false,
              onSelected: (_) => onSelect(i),
            ),
          ),
        IconButton(
          tooltip: S.rename,
          icon: const Icon(Icons.edit_outlined, size: 18),
          onPressed: onRename,
        ),
        IconButton(
          tooltip: S.delete,
          icon: const Icon(Icons.remove_circle_outline, size: 18),
          onPressed: onRemove,
        ),
        IconButton(
          tooltip: S.add,
          icon: const Icon(Icons.add_circle_outline, size: 18),
          onPressed: onAdd,
        ),
      ],
    ),
  );
}

class _FieldList extends StatelessWidget {
  const _FieldList({
    required this.scrollController,
    required this.selected,
    required this.onPick,
  });

  final ScrollController scrollController;
  final RideDataField? selected;
  final void Function(RideDataField field) onPick;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      children: [
        for (final group in RideFieldGroup.values) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
            child: Text(group.label, style: LR.fieldLabel),
          ),
          for (final field in RideDataField.values.where(
            (field) => field.group == group,
          ))
            ListTile(
              dense: true,
              title: Text(field.label),
              leading: Icon(
                field == selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: field == selected ? LR.accentDeep : LR.muted,
                size: 20,
              ),
              onTap: () => onPick(field),
            ),
        ],
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
      padding: const EdgeInsets.symmetric(vertical: 8),
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
          const SizedBox(height: 6),
          Text(
            '${layout.fieldCount}',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
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
    width: 24,
    height: 22,
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
