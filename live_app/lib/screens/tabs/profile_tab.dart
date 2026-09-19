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
import '../garage_screen.dart';
import '../profile_editor_screen.dart';
import '../safety_screen.dart';
import '../sensors_screen.dart';
import '../training_zones_screen.dart';
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
                              ? S.signedInToLiveRide
                              : '@${profile.username}',
                          style: LR.body.copyWith(fontSize: 12.5),
                        ),
                        if (profile.bio.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            profile.bio,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: LR.body.copyWith(fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: S.edit,
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ProfileEditorScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              S.displayNameHint,
              style: LR.body.copyWith(fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 24),
            LrSectionHeader(title: S.rideComputer),
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
                    title: Text(S.metricUnits),
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
                    title: Text(S.headingUp),
                    subtitle: Text(S.headingUpSubtitle),
                    value: profile.headingUp,
                    onChanged: (value) => profileService.update(
                      profile.copyWith(headingUp: value),
                    ),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.screen_lock_portrait),
                    title: Text(S.keepScreenOn),
                    value: profile.keepScreenAwake,
                    onChanged: (value) => profileService.update(
                      profile.copyWith(keepScreenAwake: value),
                    ),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.cloud_outlined),
                    title: Text(S.weather),
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
            LrSectionHeader(title: S.devicesAndServices),
            LrPanel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  AnimatedBuilder(
                    animation: services.heartRate,
                    builder: (context, _) => ListTile(
                      leading: const Icon(Icons.favorite_outline),
                      title: Text(S.whoopAndHeartRate),
                      subtitle: Text(
                        services.heartRate.isConnected
                            ? '${S.connectedTo(services.heartRate.connectedName ?? S.heartRateStrap)}'
                                  '${services.heartRate.latestBpm == null ? '' : ' · ${services.heartRate.latestBpm} bpm'}'
                            : services.heartRate.rememberedName != null
                            ? '${S.lastUsed} ${services.heartRate.rememberedName}'
                            : S.noSensorConnected,
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
                    animation: services.safety,
                    builder: (context, _) => ListTile(
                      leading: const Icon(Icons.health_and_safety_outlined),
                      title: Text(S.safety),
                      subtitle: Text(
                        services.safety.settings.isUsable
                            ? '${S.crashDetection} · '
                                  '${services.safety.settings.crashContacts.length}'
                            : S.crashDetectionNeedsContact,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SafetyScreen(),
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.insights),
                    title: Text(S.trainingZones),
                    subtitle: Text(
                      services.profile.trainingProfile.hasPowerZones ||
                              services.profile.trainingProfile.hasHeartRateZones
                          ? S.zonesReady
                          : S.zonesMissing,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const TrainingZonesScreen(),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  AnimatedBuilder(
                    animation: services.garage,
                    builder: (context, _) {
                      final due = services.garage.dueSoon;
                      return ListTile(
                        leading: const Icon(Icons.pedal_bike),
                        title: Text(S.garage),
                        subtitle: Text(
                          services.garage.bikes.isEmpty
                              ? S.garageEmpty
                              : [
                                  services.garage.bikes
                                      .map((bike) => bike.name)
                                      .join(' · '),
                                  if (due.isNotEmpty)
                                    '${S.serviceDue}: ${due.length}',
                                ].join(' — '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: due.isEmpty
                              ? null
                              : LR.body.copyWith(
                                  fontSize: 12.5,
                                  color: LR.alert,
                                ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const GarageScreen(),
                          ),
                        ),
                      );
                    },
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
                        SpotifyStatus.connected => S.connectedTo(
                          services.spotify.displayName ?? S.spotifyAccount,
                        ),
                        SpotifyStatus.connecting => S.connecting,
                        SpotifyStatus.signedOut => S.spotifyNotSignedIn,
                        SpotifyStatus.unconfigured => S.spotifyNeedsClientId,
                      }),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => widget.onOpenTab(2),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.lock_clock),
                    title: Text(S.lockScreenLiveActivity),
                    subtitle: Text(
                      switch (_liveActivitySupported) {
                        null => S.checking,
                        true => S.liveActivityReady,
                        false =>
                          Platform.isIOS ? S.liveActivityDisabled : S.iosOnly,
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
            LrSectionHeader(title: S.connection),
            LrPanel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.dns_outlined),
                    title: Text(S.liveRideServer),
                    subtitle: const Text(ApiClient.serverOrigin),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.cloud_queue),
                    title: Text(S.weatherProvider),
                    subtitle: const Text(WeatherService.endpoint),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => _logout(context, services),
              icon: const Icon(Icons.logout, size: 18),
              label: Text(S.signOut),
            ),
            const SizedBox(height: 20),
            Center(
              child: Text(
                S.appName,
                style: LR.fieldLabel.copyWith(letterSpacing: 3, fontSize: 10),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _logout(BuildContext context, AppServices services) async {
    if (services.recorder.isActive) {
      showLrMessage(context, S.finishRideBeforeSignOut, error: true);
      return;
    }
    if (services.live.isActive) await services.live.stop();
    await services.api.logout();
    unawaited(services.heartRate.disconnect());
    widget.onLogout();
  }
}
