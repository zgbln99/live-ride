import 'dart:async';

import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../models/route/route_preferences.dart';
import '../services/app_services.dart';
import '../services/route_generator.dart';
import '../services/route_intent.dart';
import '../services/route_planner.dart';
import '../services/ride_intelligence.dart';
import '../widgets/lr_common.dart';
import 'route_builder_screen.dart';

/// „Po prostu powiedz gdzie".
///
/// Dotąd zaplanowanie trasy zaczynało się od klikania punktów na mapie, czyli
/// od czynności, której nikt nie ma ochoty wykonywać w kasku przed wyjazdem.
/// Ten ekran zaczyna od zdania: nazwy miejsca, dystansu albo czasu — i dopiero
/// jeśli propozycja wymaga poprawki, otwiera kreator, który już istniał.
class RouteWizardScreen extends StatefulWidget {
  const RouteWizardScreen({super.key});

  @override
  State<RouteWizardScreen> createState() => _RouteWizardScreenState();
}

class _RouteWizardScreenState extends State<RouteWizardScreen> {
  late final AppServices _services = AppServices.of(context);
  late final RoutePlannerController _planner = RoutePlannerController(
    geocoding: _services.geocoding,
    routing: _services.routing,
    generator: RouteGenerator(_services.routing),
  );

  final TextEditingController _input = TextEditingController();
  bool _saving = false;

  /// Podkład preferencji dla wszystkich propozycji.
  ///
  /// Zdanie zawodnika nakłada się na to, a nie zastępuje: „60 km gravel"
  /// zmienia nawierzchnię i zostawia resztę taką, jak ustawił sobie na stałe.
  final RoutePreferences _preferences = const RoutePreferences();

  /// Skróty. Cztery dotknięcia zamiast wpisywania w rękawiczkach.
  static const List<int> _distances = [20, 30, 50, 75, 100, 150];
  static const List<Duration> _durations = [
    Duration(minutes: 30),
    Duration(hours: 1),
    Duration(minutes: 90),
    Duration(hours: 2),
    Duration(hours: 3),
  ];

  @override
  void dispose() {
    _planner.dispose();
    _input.dispose();
    super.dispose();
  }

  Future<void> _plan(String text) async {
    _input.text = text;
    final start =
        _services.recorder.position ?? await _services.location.lastKnown();
    // Tempo z WŁASNEJ historii, nie z prędkości chwilowej ani z założeń
    // producenta: ktoś, kto jeździ 22 km/h, po dwóch godzinach ma
    // czterdzieści cztery kilometry, a nie pięćdziesiąt.
    final history = RiderHistoryProfile.fromRides(
      await _services.rides.list(),
    );
    await _planner.plan(
      text: text,
      start: start,
      preferences: _preferences,
      movingAverageKmh: history.movingAverageKmh,
      // Wiatr decyduje o kierunku pierwszego odcinka: pod wiatr na
      // świeżych nogach, z wiatrem na powrocie.
      weather: _services.weather.current,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(S.whereTitle)),
    body: AnimatedBuilder(
      animation: _planner,
      builder: (context, _) {
        final state = _planner.state;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            TextField(
              controller: _input,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: S.whereHint,
                prefixIcon: const Icon(Icons.explore_outlined),
              ),
              onSubmitted: _plan,
            ),
            const SizedBox(height: 6),
            Text(
              S.whereExamples,
              style: LR.body.copyWith(fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 16),

            LrSectionHeader(title: S.howFar, padding: const EdgeInsets.only(bottom: 6)),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final km in _distances)
                  ActionChip(
                    label: Text('$km km'),
                    onPressed: () => _plan('$km km pętla'),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            LrSectionHeader(title: S.howLong, padding: const EdgeInsets.only(bottom: 6)),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final duration in _durations)
                  ActionChip(
                    label: Text(Fmt.durationCompact(duration)),
                    onPressed: () => _plan('${duration.inMinutes} min pętla'),
                  ),
              ],
            ),
            const SizedBox(height: 18),

            FilledButton.icon(
              onPressed: state.busy ? null : () => _plan(_input.text),
              icon: const Icon(Icons.search, size: 18),
              label: Text(state.hasResults ? S.planAgain : S.findRoutes),
            ),

            if (state.busy) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(S.plannerSearching, style: LR.body),
                ],
              ),
            ],

            if (state.failure != null) ...[
              const SizedBox(height: 18),
              // Konkretny powód i ZACHOWANY tekst: fikcyjna trasa byłaby
              // gorsza niż komunikat, a wyczyszczone pole każe wpisywać
              // wszystko od nowa.
              Text(
                switch (state.failure!) {
                  PlannerFailure.noStart => S.plannerNoStart,
                  PlannerFailure.unknownPlace => S.plannerUnknownPlace,
                  PlannerFailure.noRoute => S.plannerNoRoute,
                  PlannerFailure.offline => S.plannerOffline,
                },
                style: LR.body.copyWith(color: LR.alert, fontSize: 13),
              ),
            ],

            if (state.hasResults) ...[
              const SizedBox(height: 20),
              LrSectionHeader(
                title: S.plannerResultCount(state.routes.length),
                padding: const EdgeInsets.only(bottom: 8),
              ),
              for (final route in state.routes) ...[
                _proposal(route, state.intent),
                const SizedBox(height: 10),
              ],
            ],
          ],
        );
      },
    ),
  );

  Widget _proposal(GeneratedRoute route, RouteIntent? intent) => LrPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(route.label, style: LR.fieldValue(16)),
            ),
            // Plakietka pojawia się tylko przy wariancie, który umie
            // powiedzieć, dlaczego jest lepszy od pozostałych.
            if (route.recommended)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: LR.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  S.recommended,
                  style: LR.body.copyWith(
                    fontSize: 10.5,
                    color: LR.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            Text(
              Fmt.distance(route.distanceMeters, metric: true),
              style: LR.fieldValue(18),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '+${route.ascentMeters.round()} m · '
          '${Fmt.durationCompact(route.path.duration)}',
          style: LR.body.copyWith(fontSize: 12.5),
        ),
        // Powody wyłącznie z policzonych liczb. Wariant, którego nie da się
        // niczym uzasadnić, dostaje samą nazwę.
        for (final reason in route.reasons)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('• $reason', style: LR.body.copyWith(fontSize: 12)),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _saving ? null : () => _accept(route, intent),
                child: Text(S.rideIt),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: _saving ? null : () => _accept(route, intent, edit: true),
              child: Text(S.edit),
            ),
          ],
        ),
      ],
    ),
  );

  /// Zapisuje propozycję jako ZWYKŁĄ trasę.
  ///
  /// Ten sam zapis, co z kreatora ręcznego — inaczej połowa aplikacji
  /// (nawigacja, LIVE, GPX, synchronizacja) działałaby tylko dla jednego
  /// rodzaju tras.
  Future<void> _accept(
    GeneratedRoute route,
    RouteIntent? intent, {
    bool edit = false,
  }) async {
    setState(() => _saving = true);
    try {
      final summary = await _services.routes.saveRoute(
        name: _nameFor(route, intent),
        points: route.path.points,
        waypoints: route.waypoints,
        preferences: route.preferences,
      );
      if (!mounted) return;
      if (edit) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => RouteBuilderScreen(existing: summary),
          ),
        );
        if (mounted) Navigator.of(context).pop();
      } else {
        Navigator.of(context).pop(summary);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _nameFor(GeneratedRoute route, RouteIntent? intent) {
    final destination = intent?.destination?.trim();
    if (destination != null && destination.isNotEmpty) return destination;
    final km = (route.distanceMeters / 1000).round();
    return '$km km · ${route.label}';
  }
}

