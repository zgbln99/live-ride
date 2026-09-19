// Importing every screen forces the whole app to compile under `flutter test`,
// which catches anything the analyzer alone would let through.
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ride/main.dart';
import 'package:live_ride/screens/data_field_editor.dart';
import 'package:live_ride/screens/home_shell.dart';
import 'package:live_ride/screens/live_sheet.dart';
import 'package:live_ride/screens/login_screen.dart';
import 'package:live_ride/screens/ride_computer_screen.dart';
import 'package:live_ride/screens/ride_summary_screen.dart';
import 'package:live_ride/screens/route_detail_screen.dart';
import 'package:live_ride/screens/tabs/history_tab.dart';
import 'package:live_ride/screens/tabs/live_tab.dart';
import 'package:live_ride/screens/tabs/profile_tab.dart';
import 'package:live_ride/screens/tabs/ride_tab.dart';
import 'package:live_ride/screens/tabs/routes_tab.dart';

void main() {
  test('every screen is reachable and constructible', () {
    expect(LiveRideApp, isNotNull);
    expect(const LoginScreen(onSignedIn: _noop), isA<LoginScreen>());
    expect(HomeShell(onLogout: _noop), isA<HomeShell>());
    expect(const RideComputerScreen(), isA<RideComputerScreen>());
    expect(const RoutesTab(), isA<RoutesTab>());
    expect(const HistoryTab(), isA<HistoryTab>());
    expect(const LiveTab(), isA<LiveTab>());
    expect(const ProfileTab(onLogout: _noop), isA<ProfileTab>());
    expect(RideTab(onOpenTab: (_) {}), isA<RideTab>());
    expect(showLiveSheet, isNotNull);
    expect(showDataFieldEditor, isNotNull);
    expect(RideSummaryScreen, isNotNull);
    expect(RouteDetailScreen, isNotNull);
  });
}

void _noop() {}
