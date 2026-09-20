import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/lr_theme.dart';
import '../../i18n/strings.dart';
import '../../models/integration.dart';
import '../../models/rider_profile.dart';
import '../../models/ride_alert.dart';
import '../../services/app_services.dart';
import '../../services/spotify_service.dart';
import '../../services/weather_service.dart';
import '../../widgets/lr_common.dart';
import '../data_field_editor.dart';
import '../alert_settings_screen.dart';
import '../garage_screen.dart';
import '../integrations_screen.dart';
import '../offline_screen.dart';
import '../profile_editor_screen.dart';
import '../safety_screen.dart';
import '../segments_screen.dart';
import '../sensors_screen.dart';
import '../training_zones_screen.dart';
import '../whoop_screen.dart';
import '../workouts_screen.dart';

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
                    // Bez liczb: „próg 0,7 km/h" nic nie mówi komuś, kto
                    // chce tylko wiedzieć, czy postój na światłach wlicza
                    // się do czasu jazdy. Progi są w zaawansowanych.
                    subtitle: Text(S.autoPauseHint),
                    value: profile.autoPause,
                    onChanged: (value) => profileService.update(
                      profile.copyWith(autoPause: value),
                    ),
                  ),
                  if (profile.autoPause)
                    _AutoPauseAdvanced(
                      profile: profile,
                      onChanged: profileService.update,
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
                    animation: Listenable.merge([
                      services.sync,
                      services.offlineMaps,
                    ]),
                    builder: (context, _) => ListTile(
                      leading: const Icon(Icons.cloud_sync_outlined),
                      title: Text(S.offline),
                      subtitle: Text(
                        services.sync.pendingCount == 0
                            ? S.everythingSynced
                            : S.waitingToSync(services.sync.pendingCount),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const OfflineScreen(),
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  AnimatedBuilder(
                    animation: Listenable.merge([
                      services.strava,
                      services.health,
                    ]),
                    builder: (context, _) => ListTile(
                      leading: const Icon(Icons.cloud_upload_outlined),
                      title: Text(S.exportAndSync),
                      subtitle: Text(
                        [
                              if (services.strava.isConnected)
                                IntegrationProvider.strava.label,
                              if (services.health.isReady) S.healthTitle,
                            ].isEmpty
                            ? S.integrations
                            : [
                                if (services.strava.isConnected)
                                  IntegrationProvider.strava.label,
                                if (services.health.isReady) S.healthTitle,
                              ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const IntegrationsScreen(),
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  AnimatedBuilder(
                    animation: services.workouts,
                    builder: (context, _) => ListTile(
                      leading: const Icon(Icons.fitness_center),
                      title: Text(S.workouts),
                      subtitle: Text(
                        services.workouts.workouts.isEmpty
                            ? S.noWorkouts
                            : services.workouts.workouts
                                  .map((workout) => workout.name)
                                  .join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const WorkoutsScreen(),
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  AnimatedBuilder(
                    animation: services.segments,
                    builder: (context, _) => ListTile(
                      leading: const Icon(Icons.timer_outlined),
                      title: Text(S.segments),
                      subtitle: Text(
                        services.segments.segments.isEmpty
                            ? S.noSegments
                            : services.segments.segments
                                  .map((segment) => segment.name)
                                  .join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SegmentsScreen(),
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
            LrSectionHeader(title: S.accountSection),
            LrPanel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: Text(S.displayName),
                    subtitle: Text(profileService.riderName),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.alternate_email),
                    title: Text(S.username),
                    subtitle: Text(
                      profile.username.isEmpty ? '—' : profile.username,
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.mail_outline),
                    title: Text(S.email),
                    subtitle: Text(
                      profile.accountEmail.isEmpty ? '—' : profile.accountEmail,
                    ),
                  ),
                  const Divider(height: 1),
                  AnimatedBuilder(
                    animation: services.sync,
                    builder: (context, _) {
                      final pending = services.sync.pendingCount;
                      return ListTile(
                        leading: Icon(
                          pending == 0
                              ? Icons.cloud_done_outlined
                              : Icons.cloud_upload_outlined,
                        ),
                        title: Text(S.syncStatusLabel),
                        subtitle: Text(
                          pending == 0 ? S.syncAllDone : S.syncPending(pending),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.logout, color: LR.alert),
                    title: Text(
                      S.signOut,
                      style: const TextStyle(color: LR.alert),
                    ),
                    onTap: () => _logout(context, services),
                  ),
                ],
              ),
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

  /// Wylogowanie kasuje sesję i nic poza nią.
  ///
  /// Przejazdy, pobrane mapy i pliki GPX zostają na telefonie. Niewysłane
  /// przejazdy też: rowerzysta dostaje o nich ostrzeżenie, ale to ostrzeżenie,
  /// a nie blokada — czasem trzeba się przelogować właśnie po to, żeby coś
  /// wreszcie poszło na serwer.
  Future<void> _logout(BuildContext context, AppServices services) async {
    if (services.recorder.isActive) {
      showLrMessage(context, S.finishRideBeforeSignOut, error: true);
      return;
    }

    await services.sync.refreshPending();
    if (!context.mounted) return;
    final pending = services.sync.pendingCount;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.signOutTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (pending > 0) ...[
              Text(S.signOutUnsynced(pending)),
              const SizedBox(height: 12),
            ],
            Text(S.signOutKeepsData),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(S.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: LR.alert),
            child: Text(S.signOut),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (services.live.isActive) await services.live.stop();
    await services.api.logout();
    unawaited(services.heartRate.disconnect());
    widget.onLogout();
  }
}

/// Progi auto-pauzy, schowane przed kimś, kto ich nie szuka.
///
/// Rozwijane, a nie osobny ekran: to dwie liczby, a nie dział ustawień —
/// i domyślnie zwinięte, bo rowerzysta ma tu do podjęcia jedną decyzję,
/// włączone albo wyłączone.
class _AutoPauseAdvanced extends StatelessWidget {
  const _AutoPauseAdvanced({required this.profile, required this.onChanged});

  final RiderProfile profile;
  final ValueChanged<RiderProfile> onChanged;

  bool get _isDefault =>
      profile.autoPauseSpeedKmh == RiderProfile.defaultAutoPauseSpeedKmh &&
      profile.autoPauseDelaySeconds ==
          RiderProfile.defaultAutoPauseDelaySeconds;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: const SizedBox(width: 24),
      title: Text(S.advancedSettings, style: LR.fieldLabel),
      childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      children: [
        Text(S.autoPauseAdvancedExplainer, style: LR.body),
        const SizedBox(height: 12),
        _Slider(
          label: S.autoPauseThreshold,
          value: profile.autoPauseSpeedKmh,
          min: 0.3,
          max: 3.0,
          divisions: 27,
          format: (value) => '${value.toStringAsFixed(1)} km/h',
          onChanged: (value) => onChanged(
            profile.copyWith(
              autoPauseSpeedKmh: double.parse(value.toStringAsFixed(1)),
            ),
          ),
        ),
        _Slider(
          label: S.autoPauseDelay,
          value: profile.autoPauseDelaySeconds.toDouble(),
          min: 2,
          max: 15,
          divisions: 13,
          format: (value) => '${value.round()} s',
          onChanged: (value) => onChanged(
            profile.copyWith(autoPauseDelaySeconds: value.round()),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _isDefault
                ? null
                : () => onChanged(
                    profile.copyWith(
                      autoPauseSpeedKmh:
                          RiderProfile.defaultAutoPauseSpeedKmh,
                      autoPauseDelaySeconds:
                          RiderProfile.defaultAutoPauseDelaySeconds,
                    ),
                  ),
            child: Text(S.restoreDefaults),
          ),
        ),
      ],
    );
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: LR.body),
            Text(format(value), style: LR.fieldValue(15)),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          label: format(value),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
