import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/lr_theme.dart';
import '../../i18n/strings.dart';
import '../../models/ride_alert.dart';
import '../../services/app_services.dart';
import '../../services/spotify_service.dart';
import '../../services/weather_service.dart';
import '../../widgets/lr_common.dart';
import '../data_field_editor.dart';
import '../alert_settings_screen.dart';
import '../sensors_screen.dart';
import '../whoop_screen.dart';

/// Rider identity and app preferences.
class ProfileTab extends StatefulWidget {
  const ProfileTab({
    super.key,
    required this.onLogout,
    required this.onOpenTab,
  });

  final VoidCallback onLogout;
  final ValueChanged<int> onOpenTab;

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  bool? _liveActivitySupported;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final supported = await AppServices.of(
        context,
      ).liveActivity.isSupported();
      if (mounted) setState(() => _liveActivitySupported = supported);
    });
  }

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);

    return AnimatedBuilder(
      animation: services.profile,
      builder: (context, _) {
        final profileService = services.profile;
        final profile = profileService.profile;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            LrPanel(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  LrAvatar(
                    initials: Fmt.initials(profileService.riderName),
                    size: 54,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profileService.riderName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: LR.title.copyWith(fontSize: 20),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          profile.username.isEmpty
                              ? 'Signed in to Live Ride'
                              : '@${profile.username}',
                          style: LR.body.copyWith(fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit display name',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _editName(context, services),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Your display name is what spectators see on the LIVE map and '
              'what is stored with each recorded ride.',
              style: LR.body.copyWith(fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 24),
            const LrSectionHeader(title: 'Ride computer'),
            LrPanel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.grid_view),
                    title: Text(S.dataFields),
                    subtitle: Text(
                      profile.ridePages
                          .map(
                            (page) =>
                                '${page.name} (${page.layout.fieldCount})',
                          )
                          .join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showDataFieldEditor(context, services),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.notifications_active_outlined),
                    title: Text(S.alerts),
                    subtitle: Text(
                      AlertKind.values
                          .where(services.alerts.settings.isEnabled)
                          .map((kind) => kind.label)
                          .join(', '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AlertSettingsScreen(),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.pause_circle_outline),
                    title: Text(S.autoPauseTitle),
                    subtitle: Text(
                      profile.autoPause
                          ? '${S.autoPauseHint} '
                                '(<${profile.autoPauseSpeedKmh.round()} km/h, '
                                '${profile.autoPauseDelaySeconds} s)'
                          : S.autoPauseHint,
                    ),
                    value: profile.autoPause,
                    onChanged: (value) => profileService.update(
                      profile.copyWith(autoPause: value),
                    ),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.straighten),
                    title: const Text('Metric units'),
                    subtitle: Text(
                      profile.metricUnits ? 'km · m · km/h' : 'mi · ft · mph',
                    ),
                    value: profile.metricUnits,
                    onChanged: (value) => profileService.update(
                      profile.copyWith(metricUnits: value),
                    ),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.explore_outlined),
                    title: const Text('Heading up'),
                    subtitle: const Text('Rotate the map with your direction'),
                    value: profile.headingUp,
                    onChanged: (value) => profileService.update(
                      profile.copyWith(headingUp: value),
                    ),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.screen_lock_portrait),
                    title: const Text('Keep the screen on while riding'),
                    value: profile.keepScreenAwake,
                    onChanged: (value) => profileService.update(
                      profile.copyWith(keepScreenAwake: value),
                    ),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.cloud_outlined),
                    title: const Text('Weather'),
                    subtitle: const Text('Open-Meteo · no account required'),
                    value: profile.weatherEnabled,
                    onChanged: (value) => profileService.update(
                      profile.copyWith(weatherEnabled: value),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const LrSectionHeader(title: 'Devices and services'),
            LrPanel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  AnimatedBuilder(
                    animation: services.heartRate,
                    builder: (context, _) => ListTile(
                      leading: const Icon(Icons.favorite_outline),
                      title: const Text('WHOOP and heart rate'),
                      subtitle: Text(
                        services.heartRate.isConnected
                            ? '${services.heartRate.connectedName ?? 'Sensor'} connected'
                                  '${services.heartRate.latestBpm == null ? '' : ' · ${services.heartRate.latestBpm} bpm'}'
                            : services.heartRate.rememberedName != null
                            ? 'Last used ${services.heartRate.rememberedName}'
                            : 'No sensor connected',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const WhoopScreen(),
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  AnimatedBuilder(
                    animation: services.sensors,
                    builder: (context, _) => ListTile(
                      leading: const Icon(Icons.sensors),
                      title: Text(S.sensors),
                      subtitle: Text(
                        services.sensors.connected.isEmpty
                            ? S.noSensorsConnected
                            : services.sensors.connected
                                  .map((device) => device.name)
                                  .join(' · '),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SensorsScreen(),
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  AnimatedBuilder(
                    animation: services.spotify,
                    builder: (context, _) => ListTile(
                      leading: const Icon(Icons.graphic_eq),
                      title: const Text('Spotify'),
                      subtitle: Text(switch (services.spotify.status) {
                        SpotifyStatus.connected =>
                          '${services.spotify.displayName ?? 'Account'} connected',
                        SpotifyStatus.connecting => 'Connecting…',
                        SpotifyStatus.signedOut => 'Not signed in',
                        SpotifyStatus.unconfigured => 'Needs a client ID',
                      }),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => widget.onOpenTab(2),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.lock_clock),
                    title: const Text('Lock Screen Live Activity'),
                    subtitle: Text(
                      switch (_liveActivitySupported) {
                        null => 'Checking…',
                        true =>
                          'Ready — starts automatically when a ride starts',
                        false =>
                          Platform.isIOS
                              ? 'Turn Live Activities on for Live Ride in '
                                    'iOS Settings'
                              : 'iOS only',
                      },
                      style: TextStyle(
                        color: _liveActivitySupported == false
                            ? LR.alert
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const LrSectionHeader(title: 'Connection'),
            LrPanel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.dns_outlined),
                    title: const Text('Live Ride server'),
                    subtitle: const Text(ApiClient.serverOrigin),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.cloud_queue),
                    title: const Text('Weather provider'),
                    subtitle: const Text(WeatherService.endpoint),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => _logout(context, services),
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('SIGN OUT'),
            ),
            const SizedBox(height: 20),
            Center(
              child: Text(
                'LIVE RIDE',
                style: LR.fieldLabel.copyWith(letterSpacing: 3, fontSize: 10),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editName(BuildContext context, AppServices services) async {
    final profile = services.profile.profile;
    final controller = TextEditingController(text: profile.displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Display name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Name',
            hintText: profile.username.isEmpty ? 'Your name' : profile.username,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    await services.profile.update(profile.copyWith(displayName: name.trim()));
    if (context.mounted) {
      showLrMessage(context, 'Riding as ${services.profile.riderName}');
    }
  }

  Future<void> _logout(BuildContext context, AppServices services) async {
    if (services.recorder.isActive) {
      showLrMessage(
        context,
        'Finish your ride before signing out.',
        error: true,
      );
      return;
    }
    if (services.live.isActive) await services.live.stop();
    await services.api.logout();
    unawaited(services.heartRate.disconnect());
    widget.onLogout();
  }
}
