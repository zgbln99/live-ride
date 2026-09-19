import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../services/app_services.dart';
import '../services/sync_service.dart';
import '../widgets/lr_common.dart';

/// Tryb offline: pobrane mapy i stan synchronizacji.
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
              LrPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      S.syncExplainer,
                      style: LR.body.copyWith(fontSize: 12.5, height: 1.45),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          switch (sync.phase) {
                            SyncPhase.running => Icons.sync,
                            SyncPhase.offline => Icons.cloud_off,
                            SyncPhase.failed => Icons.error_outline,
                            SyncPhase.idle => Icons.cloud_done_outlined,
                          },
                          size: 18,
                          color: switch (sync.phase) {
                            SyncPhase.failed => LR.alert,
                            SyncPhase.offline => LR.muted,
                            _ => LR.go,
                          },
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            sync.pendingCount == 0
                                ? S.everythingSynced
                                : S.waitingToSync(sync.pendingCount),
                            style: LR.fieldValue(14),
                          ),
                        ),
                      ],
                    ),
                    if (sync.lastSuccess != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${S.lastSync}: '
                        '${Fmt.dateTime(sync.lastSuccess!)}',
                        style: LR.body.copyWith(fontSize: 12),
                      ),
                    ],
                    if (sync.lastError != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        sync.lastError!,
                        style: LR.body.copyWith(fontSize: 12, color: LR.alert),
                      ),
                    ],
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      icon: const Icon(Icons.sync, size: 18),
                      label: Text(S.syncNow),
                      onPressed: sync.isRunning
                          ? null
                          : () => sync.flush(force: true),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              LrSectionHeader(
                title: S.offlineMaps,
                padding: const EdgeInsets.only(bottom: 8),
              ),
              if (!maps.isSupported)
                LrPanel(
                  child: Text(
                    S.offlineMapsUnsupported,
                    style: LR.body.copyWith(fontSize: 12.5),
                  ),
                )
              else ...[
                Text(
                  S.offlineMapsExplainer,
                  style: LR.body.copyWith(fontSize: 12.5, height: 1.45),
                ),
                const SizedBox(height: 10),
                if (maps.current != null && !maps.current!.finished)
                  LrPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(maps.current!.routeName, style: LR.fieldValue(14)),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: maps.current!.progress,
                          minHeight: 5,
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: maps.cancelDownload,
                          child: Text(S.cancel),
                        ),
                      ],
                    ),
                  ),
                if (maps.regions.isEmpty)
                  Text(S.noOfflineMaps, style: LR.body)
                else
                  LrPanel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < maps.regions.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.map_outlined, size: 20),
                            title: Text(
                              '${maps.regions[i].metadata['route_name'] ?? S.route}',
                              style: LR.fieldValue(14),
                            ),
                            subtitle: Text(
                              'zoom ${maps.regions[i].minZoom.round()}–'
                              '${maps.regions[i].maxZoom.round()}',
                              style: LR.body.copyWith(fontSize: 11.5),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () =>
                                  maps.deleteRegion(maps.regions[i].id),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}
