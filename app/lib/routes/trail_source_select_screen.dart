import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wanderer/actions/request_background_location.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre/maplibre.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wanderer/components/route_planner/travel_profile_sheet.dart';
import 'package:wanderer/i18n/app_localizations.dart';
import 'package:wanderer/models/settings.dart';
import 'package:wanderer/provider/foreground_position_stream_provider.dart';
import 'package:wanderer/provider/online_status_provider.dart';
import 'package:wanderer/provider/settings_provider.dart';
import 'package:wanderer/provider/toast_provider.dart';
import 'package:wanderer/models/route_travel_bucket.dart';
import 'package:wanderer/services/tracelet_position_source.dart';
import 'package:wanderer/actions/import_trail_file.dart';

class TrailSourceSelectScreen extends ConsumerStatefulWidget {
  const TrailSourceSelectScreen({super.key});

  @override
  ConsumerState<TrailSourceSelectScreen> createState() =>
      _TrailSourceSelectScreenState();
}

class _TrailSourceSelectScreenState
    extends ConsumerState<TrailSourceSelectScreen> {
  bool _importLoading = false;
  bool _plannerLoading = false;
  bool _recorderLoading = false;

  Future<void> _openRecorder(AppLocalizations l10n) async {
    if (_recorderLoading) return;

    final bucket = await showTravelProfileSheet(context);
    if (!mounted || bucket == null) return;

    void showError(String text) => ref
        .read(toastProvider.notifier)
        .add(
          ToastMessage(
            type: ToastType.error,
            icon: FontAwesomeIcons.triangleExclamation,
            text: text,
          ),
        );

    if (!await Geolocator.isLocationServiceEnabled()) {
      showError(l10n.location_services_disabled);
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.deniedForever) {
      showError(l10n.location_permission_permanently_denied);
      return;
    }
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        showError(l10n.location_permission_denied);
        return;
      }
    }
    if (mounted) {
      permission = await requestBackgroundLocation(context, ref, permission);
    }

    if (!mounted) return;
    setState(() => _recorderLoading = true);
    try {
      unawaited(ref.read(onlineStatusProvider.notifier).refresh());
      final pos = await ref
          .read(foregroundPositionStreamProvider.notifier)
          .currentFix(timeout: const Duration(seconds: 20));
      if (!mounted) return;
      if (pos == null) {
        showError(l10n.location_unavailable);
        return;
      }
      context.push(
        '/record',
        extra: {
          'lat': pos.latitude,
          'lon': pos.longitude,
          'position': seedPositionFrom(pos),
          'costing': bucket.costing,
        },
      );
    } finally {
      if (mounted) setState(() => _recorderLoading = false);
    }
  }

  Future<void> _openPlanner(AppLocalizations l10n) async {
    if (_plannerLoading) return;
    final bucket = await showTravelProfileSheet(context);
    if (!mounted || bucket == null) return;

    setState(() => _plannerLoading = true);
    try {
      final center = await _resolveInitialCenter();
      if (!mounted) return;
      context.push(
        '/route-planner',
        extra: {
          'travelProfile': bucket.costing,
          'costingOptions': bucket.costingOptions,
          'lat': center.lat,
          'lon': center.lon,
        },
      );
    } finally {
      if (mounted) setState(() => _plannerLoading = false);
    }
  }

  Future<Geographic> _resolveInitialCenter() async {
    final settings = ref.read(settingsProvider);
    final fallback = _fallbackCenter(settings);

    if (settings?.behavior?.allowAutoGeolocate != true) return fallback;

    final pos = await ref
        .read(foregroundPositionStreamProvider.notifier)
        .currentFix(timeout: const Duration(seconds: 4));
    if (pos == null) return fallback;
    return Geographic(lat: pos.latitude, lon: pos.longitude);
  }

  Geographic _fallbackCenter(Settings? settings) {
    final loc = settings?.location;
    if (loc != null) return Geographic(lat: loc.lat, lon: loc.lon);
    return const Geographic(lat: 0, lon: 0);
  }

  void _showImportError(AppLocalizations l10n, [String? detail]) {
    final text = detail == null || detail.isEmpty
        ? l10n.trail_source_import_error
        : '${l10n.trail_source_import_error}\n$detail';
    ref
        .read(toastProvider.notifier)
        .add(
          ToastMessage(
            type: ToastType.error,
            icon: FontAwesomeIcons.circleExclamation,
            text: text,
          ),
        );
  }

  /// Copies the selected document into app-owned temporary storage.
  ///
  /// This is deliberate even when iOS gives file_picker a non-null path.
  /// iCloud Drive and third-party File Provider URLs can be security-scoped;
  /// once the picker closes, that path can look valid while becoming
  /// unreadable. Bytes captured while access is live are the reliable bridge.
  Future<String?> _materializePickedFile(PlatformFile picked) async {
    final safeName = picked.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final tempDir = await getTemporaryDirectory();
    final tempFile = File(
      '${tempDir.path}/${DateTime.now().microsecondsSinceEpoch}_$safeName',
    );

    final bytes = picked.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      await tempFile.writeAsBytes(bytes, flush: true);
      return tempFile.path;
    }

    final originalPath = picked.path;
    if (originalPath == null) return null;

    try {
      final original = File(originalPath);
      if (!await original.exists()) return null;
      await original.copy(tempFile.path);
      return tempFile.path;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _importGpx(AppLocalizations l10n) async {
    if (_importLoading) return;

    final isIos = Platform.isIOS;
    FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        type: isIos ? FileType.any : FileType.custom,
        allowedExtensions: isIos ? null : trailImportExtensions,
        // Always ask for bytes. This fixes iCloud/Files providers on iOS and
        // Android content URIs that do not map to a durable filesystem path.
        withData: true,
      );
    } catch (_) {
      if (mounted) {
        _showImportError(l10n, 'Nie można otworzyć aplikacji Pliki.');
      }
      return;
    }

    final picked = result?.files.single;
    if (picked == null) return;

    final dot = picked.name.lastIndexOf('.');
    final ext = (picked.extension ?? (dot >= 0 ? picked.name.substring(dot + 1) : ''))
        .toLowerCase();
    if (!trailImportExtensions.contains(ext)) {
      _showImportError(
        l10n,
        'Obsługiwane pliki: GPX, KML, KMZ, TCX i FIT.',
      );
      return;
    }

    setState(() => _importLoading = true);
    try {
      final path = await _materializePickedFile(picked);
      if (path == null) {
        if (mounted) {
          _showImportError(
            l10n,
            'Nie udało się odczytać danych pliku. Pobierz go lokalnie w aplikacji Pliki i spróbuj ponownie.',
          );
        }
        return;
      }

      if (!mounted) return;
      await importTrailFile(
        ref: ref,
        path: path,
        name: picked.name,
        navContext: context,
        l10n: l10n,
      );
    } on FileSystemException catch (e) {
      if (mounted) {
        _showImportError(l10n, 'Nie można odczytać pliku: ${e.message}');
      }
    } catch (_) {
      if (mounted) _showImportError(l10n);
    } finally {
      if (mounted) setState(() => _importLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isOnline = ref.watch(onlineStatusProvider);
    final busy = _importLoading || _plannerLoading || _recorderLoading;
    final networkBlocked = busy || !isOnline;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.new_trail),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _SourceActionCard(
            icon: FontAwesomeIcons.route,
            title: l10n.trail_source_planner,
            description: l10n.trail_source_planner_description,
            isLoading: _plannerLoading,
            onTap: networkBlocked ? null : () => _openPlanner(l10n),
          ),
          const SizedBox(height: 8),
          _SourceActionCard(
            icon: FontAwesomeIcons.solidCircleDot,
            title: l10n.trail_source_record,
            description: l10n.trail_source_record_description,
            isLoading: _recorderLoading,
            onTap: busy ? null : () => _openRecorder(l10n),
          ),
          const SizedBox(height: 8),
          _SourceActionCard(
            icon: FontAwesomeIcons.fileArrowUp,
            title: l10n.trail_source_import,
            description: l10n.trail_source_import_description,
            isLoading: _importLoading,
            onTap: busy ? null : () => _importGpx(l10n),
          ),
        ],
      ),
    );
  }
}

class _SourceActionCard extends StatelessWidget {
  final FaIconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;
  final bool isLoading;

  const _SourceActionCard({
    required this.icon,
    required this.title,
    required this.description,
    this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = onTap == null && !isLoading;

    final resolvedBgColor = disabled
        ? theme.colorScheme.onSurface.withValues(alpha: 0.05)
        : theme.colorScheme.secondaryContainer.withValues(alpha: 0.4);
    final resolvedIconColor = disabled
        ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
        : theme.colorScheme.onSurface;
    final resolvedTitleColor = disabled
        ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
        : null;
    final resolvedDescriptionColor = disabled
        ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
        : theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final resolvedBorderColor = disabled
        ? theme.colorScheme.outline.withValues(alpha: 0.3)
        : theme.colorScheme.outline;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: resolvedBorderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: resolvedBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: FaIcon(icon, color: resolvedIconColor),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: resolvedTitleColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: resolvedDescriptionColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              if (isLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                FaIcon(
                  FontAwesomeIcons.chevronRight,
                  size: 16,
                  color: disabled
                      ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
