import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/api_client.dart';
import 'core/lr_theme.dart';
import 'i18n/strings.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/app_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(LR.lightStatusBar);

  final api = ApiClient();
  await api.init();
  final services = AppServices.create(api);
  await services.warmUp();
  final signedIn = await api.hasSession();

  runApp(LiveRideApp(services: services, signedIn: signedIn));
}

class LiveRideApp extends StatefulWidget {
  const LiveRideApp({
    super.key,
    required this.services,
    required this.signedIn,
  });

  final AppServices services;
  final bool signedIn;

  @override
  State<LiveRideApp> createState() => _LiveRideAppState();
}

class _LiveRideAppState extends State<LiveRideApp> {
  late bool _signedIn = widget.signedIn;
  bool _sessionExpired = false;

  @override
  void initState() {
    super.initState();
    widget.services.api.onSessionExpired = _handleSessionExpired;
  }

  @override
  void dispose() {
    widget.services.api.onSessionExpired = null;
    super.dispose();
  }

  /// Sesja wygasła po stronie serwera.
  ///
  /// Jazda toczy się dalej: rejestrator, GPS i zapis lokalny nie mają z
  /// kontem nic wspólnego. Wylogowanie w środku przejazdu skasowałoby
  /// zawodnikowi trasę, której nie da się powtórzyć — więc ekran logowania
  /// czeka, aż przejazd się skończy.
  void _handleSessionExpired() {
    if (!_signedIn || _sessionExpired) return;
    if (widget.services.recorder.isActive) {
      _sessionExpired = true;
      widget.services.recorder.addListener(_signOutWhenRideEnds);
      return;
    }
    setState(() {
      _sessionExpired = true;
      _signedIn = false;
    });
  }

  void _signOutWhenRideEnds() {
    if (widget.services.recorder.isActive) return;
    widget.services.recorder.removeListener(_signOutWhenRideEnds);
    if (mounted) setState(() => _signedIn = false);
  }

  @override
  Widget build(BuildContext context) => AppServicesScope(
    services: widget.services,
    child: MaterialApp(
      title: 'Live Ride',
      debugShowCheckedModeBanner: false,
      theme: LR.theme(),
      home: _signedIn
          ? HomeShell(
              onLogout: () => setState(() {
                _signedIn = false;
                _sessionExpired = false;
              }),
            )
          : LoginScreen(
              notice: _sessionExpired ? S.sessionExpired : null,
              onSignedIn: () => setState(() {
                _signedIn = true;
                _sessionExpired = false;
              }),
            ),
    ),
  );
}
