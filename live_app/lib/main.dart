import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/api_client.dart';
import 'core/lr_theme.dart';
import 'i18n/strings.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/app_services.dart';
import 'services/session_guard.dart';

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

  /// Pilnuje, żeby wygasła sesja nie przerwała trwającego przejazdu.
  late final SessionGuard _session = SessionGuard(
    isRiding: () => widget.services.recorder.isActive,
    signOut: () {
      if (mounted) setState(() => _signedIn = false);
    },
  );

  @override
  void initState() {
    super.initState();
    // Odrzucone żądanie kogoś, kto i tak nie jest zalogowany, nie ma czego
    // unieważniać.
    widget.services.api.onSessionExpired = () {
      if (_signedIn) _session.onExpired();
    };
    widget.services.recorder.addListener(_session.onRideStateChanged);
  }

  @override
  void dispose() {
    widget.services.api.onSessionExpired = null;
    widget.services.recorder.removeListener(_session.onRideStateChanged);
    super.dispose();
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
                _session.reset();
              }),
            )
          : LoginScreen(
              notice: _session.expired ? S.sessionExpired : null,
              onSignedIn: () => setState(() {
                _signedIn = true;
                _session.reset();
              }),
            ),
    ),
  );
}
