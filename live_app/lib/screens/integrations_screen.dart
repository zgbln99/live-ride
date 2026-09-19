import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../models/integration.dart';
import '../models/ride_record.dart';
import '../services/app_services.dart';
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
      animation: Listenable.merge([services.strava, services.health]),
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
            const Padding(
              padding: EdgeInsets.fromLTRB(28, 2, 0, 8),
              child: SelectableText(
                'liveride',
                style: TextStyle(fontFamily: 'Menlo', fontSize: 12.5),
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
            HealthStatus.denied => S.healthDenied,
            HealthStatus.notInstalled => S.healthNotInstalled,
            HealthStatus.unsupported => S.healthUnsupported,
            HealthStatus.unknown => S.checking,
          },
          style: LR
              .fieldValue(14)
              .copyWith(color: health.isReady ? LR.go : LR.inkSoft),
        ),
        if (health.status == HealthStatus.denied ||
            health.status == HealthStatus.unknown) ...[
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
    final written = await health.exportRide(ride);
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
