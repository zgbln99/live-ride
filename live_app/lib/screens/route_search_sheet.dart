import 'dart:async';

import 'package:flutter/material.dart';

import '../core/geo.dart';
import '../core/lr_theme.dart';
import '../services/geocoding_service.dart';
import '../widgets/lr_common.dart';

/// Wyszukiwarka miejsc do kreatora tras.
Future<Place?> showRouteSearchSheet(
  BuildContext context,
  GeocodingService geocoding, {
  GeoPoint? near,
}) => showModalBottomSheet<Place>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) => Padding(
    padding: EdgeInsets.only(
      bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
    ),
    child: _SearchSheet(geocoding: geocoding, near: near),
  ),
);

class _SearchSheet extends StatefulWidget {
  const _SearchSheet({required this.geocoding, this.near});

  final GeocodingService geocoding;
  final GeoPoint? near;

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final TextEditingController _field = TextEditingController();
  Timer? _debounce;
  List<Place> _results = const [];
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    // Nominatim prosi o umiar; nie wysyłamy zapytania na każdą literę.
    _debounce = Timer(const Duration(milliseconds: 450), () => _search(value));
  }

  Future<void> _search(String value) async {
    if (value.trim().length < 3) {
      setState(() => _results = const []);
      return;
    }
    setState(() => _searching = true);
    final results = await widget.geocoding.search(value, near: widget.near);
    if (!mounted) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LrSectionHeader(title: 'Szukaj miejsca'),
          TextField(
            controller: _field,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: _search,
            decoration: InputDecoration(
              hintText: 'Miasto, ulica albo nazwa miejsca',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: _results.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      _field.text.trim().length < 3
                          ? 'Wpisz co najmniej trzy znaki.'
                          : _searching
                          ? 'Szukam…'
                          : 'Brak wyników.',
                      textAlign: TextAlign.center,
                      style: LR.body,
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _results.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final place = _results[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.place_outlined, size: 20),
                        title: Text(place.name),
                        subtitle: place.detail.isEmpty
                            ? null
                            : Text(place.detail),
                        onTap: () => Navigator.pop(context, place),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}
