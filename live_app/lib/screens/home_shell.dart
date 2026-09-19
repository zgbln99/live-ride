import 'dart:async';

import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/lr_theme.dart';
import '../services/app_services.dart';
import '../widgets/lr_common.dart';
import 'ride_computer_screen.dart';
import 'tabs/history_tab.dart';
import 'tabs/live_tab.dart';
import 'tabs/profile_tab.dart';
import 'tabs/ride_tab.dart';
import 'tabs/routes_tab.dart';

/// The Live Ride shell: five tabs, one persistent ride engine behind them.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.onLogout});

  final VoidCallback onLogout;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  static const List<({IconData icon, IconData active, String label})> _tabs = [
    (icon: Icons.play_circle_outline, active: Icons.play_circle, label: 'RIDE'),
    (icon: Icons.route_outlined, active: Icons.route, label: 'ROUTES'),
    (icon: Icons.history, active: Icons.history, label: 'HISTORY'),
    (icon: Icons.sensors_outlined, active: Icons.sensors, label: 'LIVE'),
    (icon: Icons.person_outline, active: Icons.person, label: 'PROFILE'),
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
                  const HistoryTab(),
                  const LiveTab(),
                  ProfileTab(onLogout: widget.onLogout),
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
                  child: const LrStatusChip(
                    label: 'RIDE IN PROGRESS',
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
      child: SizedBox(
        height: 58,
        child: Row(
          children: [
            for (var i = 0; i < _tabs.length; i++)
              Expanded(
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
                      const SizedBox(height: 4),
                      Text(
                        _tabs[i].label,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.7,
                          color: _tab == i ? LR.ink : LR.muted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        height: 2,
                        width: 22,
                        color: _tab == i ? LR.accent : Colors.transparent,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
