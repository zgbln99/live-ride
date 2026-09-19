import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart' show OfflineRegion;

import '../core/formatters.dart';
import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../services/app_services.dart';
import '../services/offline_map_service.dart';
import '../services/sync_service.dart';
import '../widgets/lr_common.dart';
import 'home_shell.dart';

/// Tryb offline: stan synchronizacji i pobrane mapy.
class OfflineScreen extends StatefulWidget {
  const OfflineScreen({super.key});

  @override
  State<OfflineScreen> createState() => _OfflineScreenState();
}

class _OfflineScreenState extends State<OfflineScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final services = AppServices.of(context);
      services.offlineMaps.refresh();
      services.offlineMaps.restoreStats();
      services.sync.refreshPending();
    });
  }

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);

    return AnimatedBuilder(
      animation: Listenable.merge([services.offlineMaps, services.sync]),
      builder: (context, _) {
        final maps = services.offlineMaps;
        final sync = services.sync;

        return Scaffold(
          appBar: AppBar(title: Text(S.offline)),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              LrSectionHeader(
                title: S.synchronisation,
                padding: const EdgeInsets.only(bottom: 8),
              ),
              _SyncCard(sync: sync),
              const SizedBox(height: 22),
              LrSectionHeader(
                title: S.offlineMaps,
                padding: const EdgeInsets.only(bottom: 8),
                trailing: maps.totalBytes > 0
                    ? Text(
                        Fmt.bytes(maps.totalBytes),
                        style: LR.body.copyWith(fontSize: 11.5),
                      )
                    : null,
              ),
              if (!maps.isSupported)
                LrPanel(
                  child: Text(
                    S.offlineMapsUnsupported,
                    style: LR.body.copyWith(fontSize: 12.5),
                  ),
                )
              else ...[
                if (maps.current != null && !maps.current!.finished)
                  _DownloadCard(
                    download: maps.current!,
                    onCancel: maps.cancelDownload,
                  ),
                if (maps.regions.isEmpty)
                  _EmptyMaps(onPick: () => _openRoutes(context))
                else
                  _MapList(maps: maps),
              ],
            ],
          ),
        );
      },
    );
  }

  void _openRoutes(BuildContext context) {
    // Mapy pobiera się przy trasie, a nie tutaj: pobranie potrzebuje
    // geometrii, a ta jest w bibliotece tras.
    HomeShell.openTab(context, HomeShell.tabRoutesIndex);
  }
}

/// Karta stanu synchronizacji.
///
/// Zawsze mówi jedno zdanie po polsku i nigdy nie pokazuje wyjątku
/// biblioteki HTTP — od tego jest log deweloperski.
class _SyncCard extends StatelessWidget {
  const _SyncCard({required this.sync});

  final SyncService sync;

  @override
  Widget build(BuildContext context) {
    final pending = sync.pendingCount;
    final failure = sync.failure;

    final (icon, colour, headline, detail) = switch ((sync.phase, failure)) {
      (SyncPhase.running, _) => (
        Icons.sync,
        LR.accent,
        S.syncing,
        S.syncExplainer,
      ),
      (_, SyncFailure.offline) => (
        Icons.cloud_off,
        LR.muted,
        S.syncNoInternet,
        S.syncNoInternetDetail,
      ),
      (_, SyncFailure.session) => (
        Icons.lock_outline,
        LR.alert,
        S.syncSessionExpired,
        S.syncSessionExpiredDetail,
      ),
      (_, SyncFailure.outdatedServer) => (
        Icons.update,
        LR.alert,
        S.syncOutdatedServer,
        S.syncOutdatedServerDetail,
      ),
      (_, SyncFailure.server) => (
        Icons.error_outline,
        LR.alert,
        S.syncServerError,
        S.syncServerErrorDetail,
      ),
      _ when pending > 0 => (
        Icons.cloud_upload_outlined,
        LR.accent,
        S.pendingItems(pending),
        S.syncExplainer,
      ),
      _ => (
        Icons.cloud_done_outlined,
        LR.go,
        S.everythingSynced,
        S.syncAllGoodDetail,
      ),
    };

    return LrPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: colour),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(headline, style: LR.fieldValue(15)),
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      style: LR.body.copyWith(fontSize: 12.5, height: 1.45),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (pending > 0 && sync.phase != SyncPhase.running) ...[
            const SizedBox(height: 6),
            Text(
              S.pendingItems(pending),
              style: LR.body.copyWith(fontSize: 12, color: LR.accentDeep),
            ),
          ],
          if (sync.lastSuccess != null) ...[
            const SizedBox(height: 6),
            Text(
              '${S.lastSync}: ${Fmt.dateTime(sync.lastSuccess!)}',
              style: LR.body.copyWith(fontSize: 11.5),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            icon: const Icon(Icons.sync, size: 18),
            label: Text(S.syncNow),
            onPressed: sync.isRunning ? null : () => sync.flush(force: true),
          ),
        ],
      ),
    );
  }
}

class _DownloadCard extends StatelessWidget {
  const _DownloadCard({required this.download, required this.onCancel});

  final OfflineDownload download;
  final Future<void> Function() onCancel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: LrPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(download.routeName, style: LR.fieldValue(14)),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: download.progress, minHeight: 5),
          const SizedBox(height: 8),
          TextButton(onPressed: onCancel, child: Text(S.cancel)),
        ],
      ),
    ),
  );
}

class _EmptyMaps extends StatelessWidget {
  const _EmptyMaps({required this.onPick});

  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) => LrPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.map_outlined, size: 20, color: LR.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(S.noOfflineMaps, style: LR.fieldValue(15)),
                  const SizedBox(height: 4),
                  Text(
                    S.noOfflineMapsDetail,
                    style: LR.body.copyWith(fontSize: 12.5, height: 1.45),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          icon: const Icon(Icons.route_outlined, size: 18),
          label: Text(S.pickRoute),
          onPressed: onPick,
        ),
      ],
    ),
  );
}

class _MapList extends StatelessWidget {
  const _MapList({required this.maps});

  final OfflineMapService maps;

  @override
  Widget build(BuildContext context) => LrPanel(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        for (var i = 0; i < maps.regions.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          _MapRow(region: maps.regions[i], maps: maps),
        ],
      ],
    ),
  );
}

class _MapRow extends StatelessWidget {
  const _MapRow({required this.region, required this.maps});

  final OfflineRegion region;
  final OfflineMapService maps;

  @override
  Widget build(BuildContext context) {
    final routeId = region.metadata['route_id'];
    final stats = routeId is String ? maps.statsFor(routeId) : null;
    final name =
        (region.metadata['route_name'] as String?) ??
        stats?.routeName ??
        S.route;

    // Rozmiar i data pokazują się tylko wtedy, gdy naprawdę je znamy. Mapa
    // pobrana starszą wersją aplikacji nie dostaje wymyślonych liczb.
    final facts = <String>[
      if (stats != null) '${S.mapSize}: ${Fmt.bytes(stats.bytes)}',
      if (stats != null) '${S.downloadedOn} ${Fmt.date(stats.downloadedAt)}',
      'zoom ${region.minZoom.round()}–${region.maxZoom.round()}',
    ];

    return ListTile(
      dense: true,
      leading: const Icon(Icons.map_outlined, size: 20),
      title: Text(name, style: LR.fieldValue(14)),
      subtitle: Text(
        facts.join(' · '),
        style: LR.body.copyWith(fontSize: 11.5),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _confirmDelete(context, name),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.deleteMapTitle),
        content: Text(S.deleteMapBody(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(S.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) await maps.deleteRegion(region.id);
  }
}
