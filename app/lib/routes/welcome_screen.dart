import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wanderer/components/base/wanderer_button.dart';
import 'package:wanderer/components/welcome/oauth_provider_buttons.dart';
import 'package:wanderer/components/welcome/server_selctor.dart';
import 'package:wanderer/components/welcome/topography_background.dart';
import 'package:wanderer/i18n/app_localizations.dart';
import 'package:wanderer/provider/auth_provider.dart';
import 'package:wanderer/provider/router_provider.dart';
import 'package:wanderer/provider/welcome/server_selection_provider.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverSelection = ref.watch(serverSelectionProvider);
    final authState = ref.watch(authProvider);
    final router = ref.watch(routerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: TopographyBackground()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  const Spacer(),
                  Container(
                    width: 82,
                    height: 82,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Icon(
                      Icons.navigation_rounded,
                      color: theme.colorScheme.surface,
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'LIVE RIDE',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${AppLocalizations.of(context)!.welcome_to} Live Ride',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  const Spacer(flex: 2),
                  const ServerSelector(),
                  const SizedBox(height: 24),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      WandererButton(
                        onPressed: authState.isLoading
                            ? null
                            : () => router.push('/login'),
                        primary: true,
                        disabled: serverSelection.value?.selectedServer == null,
                        child: Text(AppLocalizations.of(context)!.login),
                      ),
                      const SizedBox(height: 12),
                      WandererButton(
                        onPressed: authState.isLoading
                            ? null
                            : () => router.push('/register'),
                        secondary: true,
                        disabled: serverSelection.value?.selectedServer == null,
                        child: Text(AppLocalizations.of(context)!.register),
                      ),
                      if (serverSelection.value?.selectedServer != null)
                        OAuthProviderButtons(
                          serverUrl: serverSelection.value!.selectedServer!.url,
                        ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
