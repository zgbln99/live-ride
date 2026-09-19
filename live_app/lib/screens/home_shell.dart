import 'dart:async';

import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/api_client.dart';
import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../models/ride_route.dart';
import '../services/app_services.dart';
import '../widgets/lr_common.dart';
import 'ride_computer_screen.dart';
import 'tabs/history_tab.dart';
import 'tabs/live_tab.dart';
import 'tabs/music_tab.dart';
import 'tabs/profile_tab.dart';
import 'tabs/ride_tab.dart';
import 'tabs/routes_tab.dart';

/// The Live Ride shell: five tabs, one persistent ride engine behind them.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.onLogout});

  final VoidCallback onLogout;

  /// Numery zakładek dolnego paska. Stałe, bo odwołują się do nich ekrany
  /// spoza powłoki.
  static const int tabRideIndex = 0;
  static const int tabRoutesIndex = 1;

  /// Prośba o przełączenie zakładki z dowolnego miejsca w aplikacji.
  ///
  /// Ekran wypchnięty na stos (np. „Offline i synchronizacja") nie zna
  /// powłoki, ale bywa, że musi odesłać zawodnika tam, gdzie akcja naprawdę
  /// się wykonuje — mapy offline pobiera się przy trasie, nie w ustawieniach.
  static final ValueNotifier<int?> requestedTab = ValueNotifier<int?>(null);

  /// Wraca do powłoki i otwiera wskazaną zakładkę.
  static void openTab(BuildContext context, int index) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    requestedTab.value = index;
  }

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  AppServices? _services;

  @override
  void initState() {
    super.initState();
    HomeShell.requestedTab.addListener(_onTabRequested);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final services = AppServices.of(context);
      _services = services;
      services.deepLinks.addListener(_onDeepLink);
      unawaited(services.deepLinks.start());
      // Link, którym uruchomiono aplikację, czeka już w serwisie.
      _onDeepLink();
    });
  }

  @override
  void dispose() {
    HomeShell.requestedTab.removeListener(_onTabRequested);
    _services?.deepLinks.removeListener(_onDeepLink);
    super.dispose();
  }

  /// Trasa otwarta z linku „Otwórz w Live Ride".
  ///
  /// Pytamy, zanim cokolwiek zapiszemy: kliknięcie linku to zgoda na
  /// obejrzenie trasy, a nie na dopisanie jej do czyjejś biblioteki.
  Future<void> _onDeepLink() async {
    final services = _services;
    final token = services?.deepLinks.takeRouteToken();
    if (services == null || token == null || !mounted) return;

    final RideRoute route;
    try {
      route = await services.api.fetchSharedRoute(token);
    } on ApiException catch (e) {
      if (mounted) showLrMessage(context, e.message, error: true);
      return;
    } catch (e, stack) {
      debugPrint('Live Ride: trasa z linku: $e\n$stack');
      if (mounted) showLrMessage(context, S.routeLinkNotFound, error: true);
      return;
    }
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.routeLinkTitle),
        content: Text(
          S.routeLinkBody(
            route.name,
            '${Fmt.distance(route.distanceMeters)} ${Fmt.distanceUnit()}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(S.routeLinkAdd),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await services.routes.save(route);
    if (!mounted) return;
    showLrMessage(context, S.routeLinkImported(route.name));
    setState(() => _tab = HomeShell.tabRoutesIndex);
  }

  void _onTabRequested() {
    final index = HomeShell.requestedTab.value;
    if (index == null || index < 0 || index >= _tabs.length) return;
    HomeShell.requestedTab.value = null;
    if (mounted) setState(() => _tab = index);
  }

  /// Zakładki są getterem, a nie stałą: ich etykiety pochodzą z tekstów,
  /// a te da się podmienić w locie razem z językiem.
  static List<({IconData icon, IconData active, String label})> get _tabs => [
    (
      icon: Icons.play_circle_outline,
      active: Icons.play_circle,
      label: S.tabRide,
    ),
    (icon: Icons.route_outlined, active: Icons.route, label: S.tabRoutes),
    (icon: Icons.graphic_eq, active: Icons.graphic_eq, label: S.tabMusic),
    (icon: Icons.history, active: Icons.history, label: S.tabHistory),
    (icon: Icons.sensors_outlined, active: Icons.sensors, label: S.tabLive),
    (icon: Icons.person_outline, active: Icons.person, label: S.tabProfile),
  ];

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);

    return Scaffold(
      backgroundColor: LR.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _topBar(services),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  RideTab(onOpenTab: (index) => setState(() => _tab = index)),
                  const RoutesTab(),
                  const MusicTab(),
                  const HistoryTab(),
                  const LiveTab(),
                  ProfileTab(
                    onLogout: widget.onLogout,
                    onOpenTab: (index) => setState(() => _tab = index),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _bottomBar(),
    );
  }

  Widget _topBar(AppServices services) => AnimatedBuilder(
    animation: Listenable.merge([services.profile, services.recorder]),
    builder: (context, _) {
      final recorder = services.recorder;
      return Container(
        height: 54,
        padding: const EdgeInsets.fromLTRB(16, 0, 10, 0),
        decoration: const BoxDecoration(
          color: LR.surface,
          border: Border(bottom: BorderSide(color: LR.line)),
        ),
        child: Row(
          children: [
            const LrWordmark(),
            const Spacer(),
            if (recorder.isActive)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  onTap: _openRideComputer,
                  child: LrStatusChip(
                    label: S.rideInProgress,
                    color: LR.alert,
                    filled: true,
                  ),
                ),
              ),
            LrAvatar(
              initials: Fmt.initials(services.profile.riderName),
              size: 34,
            ),
          ],
        ),
      );
    },
  );

  void _openRideComputer() {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const RideComputerScreen()),
      ),
    );
  }

  Widget _bottomBar() => Container(
    decoration: const BoxDecoration(
      color: LR.surface,
      border: Border(top: BorderSide(color: LR.line)),
    ),
    child: SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Six labelled tabs need about 56 pt each. On a narrow phone the
          // labels go and the icons stay, rather than the labels colliding.
          final showLabels = constraints.maxWidth / _tabs.length >= 56;
          return SizedBox(
            height: showLabels ? 58 : 50,
            child: Row(
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  Expanded(
                    child: Semantics(
                      selected: _tab == i,
                      button: true,
                      label: _tabs[i].label,
                      child: InkWell(
                        onTap: () => setState(() => _tab = i),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _tab == i ? _tabs[i].active : _tabs[i].icon,
                              size: 21,
                              color: _tab == i ? LR.ink : LR.muted,
                            ),
                            if (showLabels) ...[
                              const SizedBox(height: 4),
                              Text(
                                _tabs[i].label,
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                  color: _tab == i ? LR.ink : LR.muted,
                                ),
                              ),
                            ],
                            const SizedBox(height: 3),
                            Container(
                              height: 2,
                              width: 20,
                              color: _tab == i ? LR.accent : Colors.transparent,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
