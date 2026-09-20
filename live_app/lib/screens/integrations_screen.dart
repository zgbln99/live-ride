import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../models/integration.dart';
import '../models/ride_record.dart';
import '../services/app_services.dart';
import 'package:health/health.dart';

import '../services/apple_watch_service.dart';
import '../services/health_service.dart';
import '../services/strava_service.dart';
import '../widgets/lr_common.dart';

/// Eksport przejazdów: pliki, Strava, Apple Health / Health Connect.
class IntegrationsScreen extends StatefulWidget {
  const IntegrationsScreen({super.key, this.ride});

  /// Gdy podany, ekran pokazuje też akcje wysyłki tego przejazdu.
  final RecordedRide? ride;

  @override
  State<IntegrationsScreen> createState() => _IntegrationsScreenState();
}

class _IntegrationsScreenState extends State<IntegrationsScreen> {
  final _clientId = TextEditingController();
  final _clientSecret = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final credentials = AppServices.of(context).strava.credentials;
      _clientId.text = credentials.clientId;
      _clientSecret.text = credentials.clientSecret;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _clientId.dispose();
    _clientSecret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);

    return AnimatedBuilder(
      animation: Listenable.merge([
        services.strava,
        services.health,
        services.watch,
      ]),
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(S.exportAndSync)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (widget.ride != null) ...[
              LrSectionHeader(
                title: S.exportFile,
                padding: const EdgeInsets.only(bottom: 8),
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.description_outlined, size: 18),
                      label: const Text('GPX'),
                      onPressed: () => _shareFile(gpx: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.description_outlined, size: 18),
                      label: const Text('TCX'),
                      onPressed: () => _shareFile(gpx: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
            ],

            LrSectionHeader(
              title: IntegrationProvider.strava.label,
              padding: const EdgeInsets.only(bottom: 8),
            ),
            _stravaPanel(services.strava),
            const SizedBox(height: 22),

            LrSectionHeader(
              title: S.healthTitle,
              padding: const EdgeInsets.only(bottom: 8),
            ),
            _healthPanel(services.health),
            const SizedBox(height: 18),
            LrSectionHeader(title: S.watchTitle),
            _watchPanel(services.watch),
            const SizedBox(height: 22),

            for (final provider in [
              IntegrationProvider.komoot,
              IntegrationProvider.garmin,
            ]) ...[
              LrSectionHeader(
                title: provider.label,
                padding: const EdgeInsets.only(bottom: 8),
              ),
              LrPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 16,
                          color: LR.muted,
                        ),
                        const SizedBox(width: 8),
                        Text(S.noPublicApi, style: LR.fieldLabel),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      S.noPublicApiMessage(provider.label),
                      style: LR.body.copyWith(fontSize: 12.5, height: 1.45),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stravaPanel(StravaService strava) {
    final upload = strava.lastUpload;
    return LrPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (strava.isConnected) ...[
            Row(
              children: [
                const Icon(Icons.check_circle, color: LR.go, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    strava.credentials.athleteName ??
                        IntegrationProvider.strava.label,
                    style: LR.fieldValue(15),
                  ),
                ),
                TextButton(
                  onPressed: strava.disconnect,
                  child: Text(S.disconnect),
                ),
              ],
            ),
            if (widget.ride != null) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.cloud_upload_outlined, size: 18),
                label: Text(S.uploadToStrava),
                onPressed: _busy ? null : _uploadToStrava,
              ),
            ],
            if (upload != null) ...[
              const SizedBox(height: 8),
              Text(
                switch (upload.state) {
                  UploadState.done => S.uploadDone,
                  UploadState.processing => S.uploadProcessing,
                  UploadState.failed => '${S.uploadFailed}: ${upload.error}',
                  _ => '',
                },
                style: LR.body.copyWith(
                  fontSize: 12.5,
                  color: upload.state == UploadState.failed
                      ? LR.alert
                      : LR.inkSoft,
                ),
              ),
            ],
          ] else ...[
            Text(S.stravaSetupTitle, style: LR.fieldLabel),
            const SizedBox(height: 6),
            Text(
              S.stravaSetupIntro,
              style: LR.body.copyWith(fontSize: 12.5, height: 1.45),
            ),
            const SizedBox(height: 12),
            _step(1, S.stravaStep1),
            _step(2, S.stravaStep2),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 2, 0, 8),
              // Domena adresu powrotnego, a nie schemat. Strava sprawdza
              // HOST, więc wpisanie tu „liveride" kończy się odrzuceniem
              // logowania z błędem `redirect_uri invalid`.
              child: SelectableText(
                StravaService.callbackHost,
                style: const TextStyle(fontFamily: 'Menlo', fontSize: 12.5),
              ),
            ),
            _step(3, S.stravaStep3),
            const SizedBox(height: 10),
            TextField(
              controller: _clientId,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Client ID'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _clientSecret,
              autocorrect: false,
              obscureText: true,
              decoration: InputDecoration(labelText: S.clientSecret),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : () => _connectStrava(strava),
              child: Text(S.connectStrava),
            ),
            if (strava.lastError != null) ...[
              const SizedBox(height: 10),
              Text(
                strava.lastError!,
                style: LR.body.copyWith(fontSize: 12.5, color: LR.alert),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _healthPanel(HealthService health) => LrPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          S.healthIntro,
          style: LR.body.copyWith(fontSize: 12.5, height: 1.45),
        ),
        const SizedBox(height: 10),
        Text(
          switch (health.status) {
            HealthStatus.ready => S.healthReady,
            HealthStatus.partial => S.healthPartial,
            HealthStatus.denied => S.healthDenied,
            HealthStatus.notInstalled => S.healthNotInstalled,
            HealthStatus.unsupported => S.healthUnsupported,
            HealthStatus.unknown => S.checking,
          },
          style: LR.fieldValue(14).copyWith(
            color: switch (health.status) {
              HealthStatus.ready => LR.go,
              HealthStatus.partial => LR.alert,
              HealthStatus.denied => LR.alert,
              _ => LR.inkSoft,
            },
          ),
        ),
        // Konkretny powód zamiast „nie udało się". Komunikat platformy jest
        // jedyną rzeczą, która odróżnia brak zgody od braku HealthKitu na
        // tym urządzeniu.
        if (health.lastError != null && health.lastError!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            health.lastError!,
            style: LR.body.copyWith(fontSize: 11.5, color: LR.alert),
          ),
        ],
        if (health.status != HealthStatus.unsupported &&
            health.status != HealthStatus.notInstalled) ...[
          const SizedBox(height: 14),
          Text(S.healthWriteSection, style: LR.fieldLabel),
          const SizedBox(height: 4),
          _healthLine(S.healthWriteWorkout, health.canWrite),
          _healthLine(S.healthWriteDistance, health.canWrite),
          _healthLine(S.healthWriteEnergy, health.canWrite),
          // Trasa treningu wymaga JEDNEGO I DRUGIEGO: zapisu, bo ją
          // dopisujemy, i odczytu, bo bez odczytania świeżo zapisanego
          // treningu nie znamy jego identyfikatora, a HealthKit go wymaga.
          _healthLine(
            S.healthWriteRoute,
            health.canWrite && health.readEnabled,
          ),

          const SizedBox(height: 14),
          Text(S.healthReadSection, style: LR.fieldLabel),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              S.healthReadToggle,
              style: LR.body.copyWith(color: LR.ink, fontSize: 14),
            ),
            subtitle: Text(
              S.healthReadHint,
              style: LR.body.copyWith(fontSize: 11.5),
            ),
            value: health.readEnabled,
            onChanged: health.setReadEnabled,
          ),
          if (health.readEnabled) ...[
            _healthReadLine(S.healthReadHeartRate, health, HealthDataType.HEART_RATE),
            _healthReadLine(
              S.healthReadResting,
              health,
              HealthDataType.RESTING_HEART_RATE,
            ),
            _healthReadLine(S.healthReadWeight, health, HealthDataType.WEIGHT),
            _healthReadLine(S.healthReadWorkouts, health, HealthDataType.WORKOUT),
            _healthReadLine(
              S.healthReadDistance,
              health,
              HealthDataType.DISTANCE_CYCLING,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                S.healthReadUnknownHint,
                style: LR.body.copyWith(fontSize: 11, height: 1.35),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                S.healthAdvancedToggle,
                style: LR.body.copyWith(color: LR.ink, fontSize: 14),
              ),
              subtitle: Text(
                S.healthAdvancedHint,
                style: LR.body.copyWith(fontSize: 11.5),
              ),
              value: health.advancedEnabled,
              onChanged: health.setAdvancedEnabled,
            ),
          ],
        ],
        if (!health.canWrite && health.status != HealthStatus.unsupported) ...[
          const SizedBox(height: 10),
          FilledButton(
            onPressed: health.requestPermission,
            child: Text(S.healthGrant),
          ),
        ],
        if (health.status != HealthStatus.unsupported)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(S.healthAutoExport),
            value: health.autoExport,
            onChanged: health.setAutoExport,
          ),
        if (widget.ride != null && health.status != HealthStatus.unsupported)
          OutlinedButton.icon(
            icon: const Icon(Icons.favorite_border, size: 18),
            label: Text(S.healthTitle),
            onPressed: () => _exportToHealth(health),
          ),
      ],
    ),
  );

  /// Jedna pozycja listy: nazwa i czy działa.
  Widget _healthLine(String label, bool ok, {String? detail}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          ok ? Icons.check : Icons.remove,
          size: 16,
          color: ok ? LR.go : LR.muted,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            detail == null ? label : '$label · $detail',
            style: LR.body.copyWith(
              fontSize: 13,
              color: ok ? LR.ink : LR.inkSoft,
            ),
          ),
        ),
      ],
    ),
  );

  /// To samo dla odczytu, gdzie „nie wiemy" jest osobnym, uczciwym stanem.
  Widget _healthReadLine(
    String label,
    HealthService health,
    HealthDataType type,
  ) {
    final state = health.readState(type);
    return _healthLine(
      label,
      state == HealthReadState.working,
      detail: switch (state) {
        HealthReadState.working => S.healthStateWorking,
        HealthReadState.requested => S.healthStateRequested,
        HealthReadState.denied => S.healthStateDenied,
        HealthReadState.notRequested => S.healthStateNotRequested,
      },
    );
  }

  /// Apple Watch to OSOBNA integracja, nie część Apple Health.
  ///
  /// Mylenie ich jest najczęstszym nieporozumieniem wokół tętna na iPhonie:
  /// zgoda na Health nie sprawia, że zegarek zacznie nadawać na żywo, a
  /// odczyt z HealthKit daje próbki sprzed dziesiątek sekund.
  Widget _watchPanel(AppleWatchService watch) => LrPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          S.watchHint,
          style: LR.body.copyWith(fontSize: 12.5, height: 1.45),
        ),
        const SizedBox(height: 10),
        _healthLine(
          S.watchLiveHeartRate,
          watch.state == WatchState.streaming,
          detail: switch (watch.state) {
            WatchState.streaming => S.watchStreaming,
            WatchState.ready => S.watchReady,
            WatchState.notPaired => S.watchNotPaired,
            WatchState.notInstalled => S.watchNotInstalled,
            WatchState.unknown => S.watchUnknown,
          },
        ),
      ],
    ),
  );

  Widget _step(int number, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 22, child: Text('$number.', style: LR.fieldValue(13))),
        Expanded(child: Text(text, style: LR.body.copyWith(fontSize: 12.5))),
      ],
    ),
  );

  Future<void> _connectStrava(StravaService strava) async {
    setState(() => _busy = true);
    await strava.setCredentials(
      clientId: _clientId.text,
      clientSecret: _clientSecret.text,
    );
    await strava.connect();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _uploadToStrava() async {
    final ride = widget.ride;
    if (ride == null) return;
    setState(() => _busy = true);
    final services = AppServices.of(context);
    try {
      final file = await services.rides.exportTcx(ride);
      await services.strava.uploadRide(ride, file);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportToHealth(HealthService health) async {
    final ride = widget.ride;
    if (ride == null) return;
    // Trasa jedzie razem z treningiem: HealthKit umie ją przyjąć, a trening
    // rowerowy bez śladu jest w Health tylko liczbą.
    final written = await health.exportRide(
      ride,
      track: [for (final point in ride.points) point.geo],
    );
    if (!mounted) return;
    showLrMessage(
      context,
      written ? S.exportedToHealth : health.lastError ?? S.healthDenied,
      error: !written,
    );
  }

  Future<void> _shareFile({required bool gpx}) async {
    final ride = widget.ride;
    if (ride == null) return;
    final services = AppServices.of(context);
    final File file = gpx
        ? await services.rides.exportGpx(ride)
        : await services.rides.exportTcx(ride);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: ride.name),
    );
  }
}
