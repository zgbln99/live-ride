import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/api_client.dart';
import 'core/lr_theme.dart';
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

  @override
  Widget build(BuildContext context) => AppServicesScope(
    services: widget.services,
    child: MaterialApp(
      title: 'Live Ride',
      debugShowCheckedModeBanner: false,
      theme: LR.theme(),
      home: _signedIn
          ? HomeShell(onLogout: () => setState(() => _signedIn = false))
          : LoginScreen(onSignedIn: () => setState(() => _signedIn = true)),
    ),
  );
}
