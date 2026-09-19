import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanderer/provider/router_provider.dart';

const Duration _revealDuration = Duration(milliseconds: 700);
const Duration _revealDeadline = Duration(milliseconds: 3000);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;
  Timer? _failsafe;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _revealDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _releaseHold();
      });
    _scale = CurvedAnimation(parent: _controller, curve: Curves.easeOutBack);
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _failsafe = Timer(_revealDeadline, _releaseHold);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      _releaseHold();
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _failsafe?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _releaseHold() {
    _failsafe?.cancel();
    _failsafe = null;
    if (!mounted) return;
    ref.read(splashRevealProvider.notifier).complete();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF070B10) : const Color(0xFFF7FAFC);
    final foreground = dark ? Colors.white : const Color(0xFF071018);

    return Scaffold(
      backgroundColor: background,
      body: Center(
        child: Semantics(
          label: 'Live Ride',
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 86,
                    height: 86,
                    decoration: BoxDecoration(
                      color: const Color(0xFF18D9FF),
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x3318D9FF),
                          blurRadius: 34,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.navigation_rounded,
                      size: 50,
                      color: Color(0xFF061017),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'LIVE RIDE',
                    style: TextStyle(
                      color: foreground,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'NAVIGATE  •  RIDE  •  SHARE LIVE',
                    style: TextStyle(
                      color: foreground.withValues(alpha: .46),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
