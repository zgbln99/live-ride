import 'dart:async';

import 'package:flutter/material.dart';

import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../services/app_services.dart';
import '../widgets/lr_common.dart';

/// Diagnostyka publicznego LIVE dla właściciela jazdy.
///
/// Odpowiada na jedno pytanie, którego aplikacja dotąd nie umiała zadać: co
/// z tego, co licznik wysyła, SERWER naprawdę przyjął. Telefon zna własne
/// czujniki i własną nawigację, więc widok „u mnie działa" nigdy nie tłumaczył
/// pustej publicznej strony. Najczęstsze przyczyny — trasa nieprzypięta do
/// sesji i tętno wyłączone przełącznikiem prywatności — nie były błędami:
/// serwer w obu wypadkach robił dokładnie to, o co go poproszono, i nie miał
/// powodu niczego zgłaszać.
///
/// Ekran jest prywatny. Nie pokazuje go żaden widz i nie ma go w publicznym
/// API — wymaga zalogowania i własności sesji.
Future<void> showLiveDiagnosticsSheet(
  BuildContext context,
  AppServices services,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, controller) =>
          _LiveDiagnostics(services: services, scrollController: controller),
    ),
  );
}

class _LiveDiagnostics extends StatefulWidget {
  const _LiveDiagnostics({
    required this.services,
    required this.scrollController,
  });

  final AppServices services;
  final ScrollController scrollController;

  @override
  State<_LiveDiagnostics> createState() => _LiveDiagnosticsState();
}

class _LiveDiagnosticsState extends State<_LiveDiagnostics> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _unreachable = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    // Pięć sekund: diagnostyka ma pokazywać zmianę po dotknięciu przełącznika,
    // ale nie ma powodu obciążać łącza tak jak publiczna strona.
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => unawaited(_refresh()));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final session = widget.services.live.session;
    if (session == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final data = await widget.services.api.liveDiagnostics(session.id);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _unreachable = data == null;
      if (data != null) _data = data;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.services.live.session;

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      children: [
        Row(
          children: [
            Expanded(
              child: LrSectionHeader(
                title: S.liveDiagnostics,
                padding: const EdgeInsets.only(bottom: 4),
              ),
            ),
            const LrSheetClose(),
          ],
        ),
        Text(
          S.diagnosticsSubtitle,
          style: LR.body.copyWith(fontSize: 12.5, height: 1.4),
        ),
        const SizedBox(height: 14),

        if (session == null)
          Text(S.diagnosticsNoSession, style: LR.body)
        else if (_loading && _data == null)
          const Center(child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(strokeWidth: 2),
          ))
        else ...[
          if (_unreachable)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                S.diagnosticsUnreachable,
                style: LR.body.copyWith(fontSize: 12.5, color: LR.alert),
              ),
            ),
          ..._rows(),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(S.diagnosticsRefresh),
            onPressed: () => unawaited(_refresh()),
          ),
        ],
      ],
    );
  }

  List<Widget> _rows() {
    final data = _data;
    if (data == null) return const [];

    final session = _map(data['session']);
    final telemetry = _map(data['telemetry']);
    final route = _map(data['route']);
    final privacy = _map(data['privacy']);

    return [
      _signal(
        label: S.diagnosticsServer,
        ok: !_unreachable,
        value: telemetry['seq'] == null ? '—' : 'seq ${telemetry['seq']}',
        detail: _age(telemetry['age_seconds']),
      ),
      _signal(
        label: 'GPS',
        ok: _map(data['gps'])['present'] == true,
        value: _accuracy(_map(data['gps'])['accuracy_m']),
        detail: _age(_map(data['gps'])['age_seconds']),
      ),
      _routeRow(route),
      _navRow(_map(data['navigation'])),
      _sensor(
        label: 'HR',
        signal: _map(data['heart_rate']),
        unit: 'bpm',
        valueKey: 'bpm',
      ),
      _sensor(
        label: 'MOC',
        signal: _map(data['power']),
        unit: 'W',
        valueKey: 'watts',
      ),
      _sensor(
        label: 'KADENCJA',
        signal: _map(data['cadence']),
        unit: 'rpm',
        valueKey: 'rpm',
      ),
      _signal(
        label: 'BATERIA TELEFONU',
        ok: data['phone_battery'] != null,
        value: data['phone_battery'] == null
            ? S.diagnosticsMissing
            : '${data['phone_battery']} %',
      ),
      _signal(
        label: S.diagnosticsViewers,
        ok: true,
        value: '${session['viewers'] ?? 0}',
      ),
      if (privacy['location_delay_seconds'] is num &&
          (privacy['location_delay_seconds'] as num) > 0)
        _signal(
          label: S.locationDelay,
          ok: true,
          value: '${privacy['location_delay_seconds']} s',
        ),
    ];
  }

  Widget _routeRow(Map<String, dynamic> route) {
    final attached = route['attached'] == true;
    final distance = route['distance_m'];
    return _signal(
      label: S.diagnosticsRoute,
      ok: attached,
      value: attached && distance is num
          ? '${(distance / 1000).toStringAsFixed(1)} km'
          : (attached ? '✓' : S.diagnosticsMissing),
      detail: attached
          ? 'rev ${route['revision'] ?? 0}'
          // Najczęstsza usterka publicznego LIVE, napisana wprost zamiast
          // zostawiona do odgadnięcia z pustej mapy.
          : S.diagnosticsNoRoute,
    );
  }

  Widget _navRow(Map<String, dynamic> nav) {
    final present = nav['present'] == true;
    final offRoute = nav['off_route'] == true;
    return _signal(
      label: S.diagnosticsNav,
      ok: present && !offRoute,
      value: offRoute
          ? 'POZA TRASĄ'
          : (present ? _distance(nav['distance_m']) : S.diagnosticsMissing),
      detail: nav['instruction'] as String?,
    );
  }

  Widget _sensor({
    required String label,
    required Map<String, dynamic> signal,
    required String unit,
    required String valueKey,
  }) {
    final shared = signal['shared'] == true;
    final value = signal[valueKey];
    final hasValue = value is num && value > 0;
    final battery = signal['battery'];
    final source = signal['source'] as String?;

    return _signal(
      label: label,
      ok: shared && hasValue,
      // Rozróżnienie, którego brak kosztował najwięcej czasu: „nie mam
      // czujnika" i „mam czujnik, ale sam zabroniłem go pokazywać" to dwie
      // zupełnie różne przyczyny pustego pola na publicznej stronie.
      value: !shared
          ? S.diagnosticsHidden
          : (hasValue ? '$value $unit' : S.diagnosticsMissing),
      detail: [
        if (source != null && source.isNotEmpty) source,
        if (battery is num) '$battery %',
        ?_age(signal['age_seconds']),
      ].join(' · '),
    );
  }

  Widget _signal({
    required String label,
    required bool ok,
    required String value,
    String? detail,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          ok ? Icons.check_circle : Icons.remove_circle_outline,
          size: 18,
          color: ok ? LR.go : LR.muted,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: LR.fieldLabel),
              Text(value, style: LR.fieldValue(16)),
              if (detail != null && detail.isNotEmpty)
                Text(detail, style: LR.body.copyWith(fontSize: 11.5)),
            ],
          ),
        ),
      ],
    ),
  );

  Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};

  String? _age(Object? seconds) {
    if (seconds is! num) return null;
    final value = seconds.round();
    if (value < 2) return 'przed chwilą';
    if (value < 60) return '$value s temu';
    return '${value ~/ 60} min temu';
  }

  String _accuracy(Object? meters) {
    if (meters is! num || meters <= 0) return '✓';
    return '±${meters.round()} m';
  }

  String _distance(Object? meters) {
    if (meters is! num) return '—';
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }
}
