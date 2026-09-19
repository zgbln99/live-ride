import 'package:flutter/material.dart';

import 'core/api_client.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/gpx_service.dart';
import 'services/heart_rate_service.dart';
import 'services/live_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiClient();
  await api.init();
  runApp(LiveRideApp(api: api));
}

class LiveRideApp extends StatefulWidget {
  const LiveRideApp({super.key, required this.api});

  final ApiClient api;

  @override
  State<LiveRideApp> createState() => _LiveRideAppState();
}

class _LiveRideAppState extends State<LiveRideApp> {
  late final GpxService _gpx = GpxService();
  late final HeartRateService _heartRate = HeartRateService();
  late final LiveSessionController _live = LiveSessionController(widget.api, _heartRate);
  late Future<bool> _session = widget.api.hasSession();

  @override
  void dispose() {
    _heartRate.dispose();
    super.dispose();
  }

  void _loggedIn() => setState(() => _session = Future.value(true));
  void _loggedOut() => setState(() => _session = Future.value(false));

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF00BFD8),
      brightness: Brightness.light,
      surface: const Color(0xFFF7F9FB),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Live Ride',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFF7F9FB),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFE5E9EE)),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF7F9FB),
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
          titleTextStyle: TextStyle(color: Color(0xFF071018), fontSize: 24, fontWeight: FontWeight.w900),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: Color(0x3319D8FF),
        ),
      ),
      home: FutureBuilder<bool>(
        future: _session,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.data != true) {
            return LoginScreen(api: widget.api, onLoggedIn: _loggedIn);
          }
          return HomeScreen(
            api: widget.api,
            gpx: _gpx,
            heartRate: _heartRate,
            live: _live,
            onLogout: _loggedOut,
          );
        },
      ),
    );
  }
}
