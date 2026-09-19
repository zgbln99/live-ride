import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:gpx/gpx.dart';
import 'package:path/path.dart' as p;
import 'package:wanderer/i18n/app_localizations.dart';
import 'package:wanderer/models/trail.dart';
import 'package:wanderer/provider/api_provider.dart';
import 'package:wanderer/provider/online_status_provider.dart';
import 'package:wanderer/provider/toast_provider.dart';
import 'package:wanderer/util/gpx/conversion.dart';
import 'package:wanderer/util/gpx/gpx.dart';
import 'package:wanderer/util/geo/reverse_geocode.dart';
import 'package:wanderer/util/route/planner_handoff.dart';
import 'package:wanderer/actions/resolve_track_save_options.dart';

const trailImportExtensions = ['gpx', 'kml', 'kmz', 'tcx', 'fit'];

Trail? pendingImportedTrail;

Future<void> importTrailFile({
  required WidgetRef ref,
  required String path,
  required String name,
  required BuildContext navContext,
  required AppLocalizations l10n,
}) async {
  void showError(String text) {
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

  final ext = p.extension(name).replaceFirst('.', '').toLowerCase();
  if (ext.isEmpty || !trailImportExtensions.contains(ext)) {
    showError(l10n.trail_source_import_error);
    return;
  }

  final isOffline = await ref
      .read(onlineStatusProvider.notifier)
      .refresh()
      .then((online) => !online);

  if (ext != 'gpx' && isOffline) {
    showError(l10n.trail_source_offline_import_error);
    return;
  }

  final Trail trail;
  try {
    final gpxXml = ext == 'gpx'
        ? await File(path).readAsString()
        : await transcodeToGpx(ref, path, name);

    // Keep the parsed GPX on the same isolate. A GPX document is a graph of
    // custom Dart objects and moving that graph through Flutter's compute()
    // boundary is fragile on real devices. Files of the size typically used
    // for cycling routes parse comfortably in-process and this keeps the
    // import path deterministic on iOS/Android.
    final gpx = parseGpxSafely(gpxXml);

    final hasUsablePoint =
        gpx.allWaypoints.isNotEmpty ||
        gpx.rtes.any(
          (r) => r.rtepts.any((p) => p.lat != null && p.lon != null),
        );
    if (!hasUsablePoint) {
      debugPrint(
        'importTrailFile: "$name" contains no track point with both lat '
        'and lon; refusing to import an empty trail',
      );
      showError(l10n.trail_source_import_error);
      return;
    }

    // A native GPX is already the final geometry. Import it immediately and
    // let the user edit/recalculate later instead of making successful import
    // depend on an extra online options sheet.
    if (ext == 'gpx') {
      trail = await buildLocalTrail(
        ref,
        gpx,
        fallbackName: name,
        gpxData: gpxXml,
      );
    } else {
      if (!navContext.mounted) return;
      final options = await resolveTrackSaveOptions(
        ref,
        navContext,
        TrackSaveOptionsSource.import,
      );
      if (options == null) return;
      if (!navContext.mounted) return;

      final (recalcHeights, followRoads) = options;
      var finalGpx = gpx;
      var finalGpxData = gpxXml;

      if (recalcHeights || followRoads) {
        final points = gpx.allPoints;
        var workingShape = [
          for (final point in points) {'lat': point.lat, 'lon': point.lon},
        ];

        if (followRoads && workingShape.length >= 2) {
          workingShape = await snapShapeToRoads(
            ref,
            buildNavShape(points),
            'pedestrian',
            fallbackShape: workingShape,
          );
        }

        var heights = const <num>[];
        if (recalcHeights && workingShape.length >= 2) {
          heights = await fetchHeightsForShape(ref, workingShape);
        }

        final originalWaypoints = gpx.allWaypoints;
        finalGpx = mergeHeightsIntoGpx(
          workingShape,
          heights,
          startTime: originalWaypoints.firstOrNull?.time,
          endTime: originalWaypoints.lastOrNull?.time,
          source: gpx,
        );
        finalGpxData = serializeGpxToXml(finalGpx);
      }

      trail = await buildLocalTrail(
        ref,
        finalGpx,
        fallbackName: name,
        gpxData: finalGpxData,
      );
    }
  } catch (e, st) {
    debugPrint('importTrailFile failed for "$name": $e\n$st');
    showError('${l10n.trail_source_import_error}\n$e');
    return;
  }

  pendingImportedTrail = trail;
  if (!navContext.mounted) return;
  navContext.push('/trail/create/edit', extra: trail);
}

Future<String> transcodeToGpx(WidgetRef ref, String path, String name) async {
  final formData = FormData.fromMap({
    'file': await MultipartFile.fromFile(path, filename: name),
  });
  final res = await ref
      .read(apiProvider)
      .post('/trail/convert', data: formData);

  final data = res.data;
  if (data is String && data.isNotEmpty) {
    return data;
  }
  if (data is Map) {
    final expand = data['expand'] as Map<String, dynamic>?;
    final gpxData = expand?['gpx_data'] as String?;
    if (gpxData != null && gpxData.isNotEmpty) {
      return gpxData;
    }
  }
  throw StateError(
    'transcodeToGpx: convert endpoint response contained no usable GPX data',
  );
}

Future<Trail> buildLocalTrail(
  WidgetRef ref,
  Gpx gpx, {
  String? fallbackName,
  Duration? movingDuration,
  String? gpxData,
}) async {
  final trail = trailFromGpx(
    gpx,
    fallbackName: fallbackName,
    movingDuration: movingDuration,
    gpxData: gpxData,
  );

  final lat = trail.lat;
  final lon = trail.lon;
  if (ref.read(onlineStatusProvider) && lat != null && lon != null) {
    try {
      final result = await searchLocationReverseStructured(
        ref.read(apiProvider),
        lat,
        lon,
        includeRoad: false,
      );
      if (result != null && result.fullLabel.isNotEmpty) {
        return trail.copyWith(location: result.fullLabel);
      }
    } catch (_) {
      // Best-effort only — never blocks the save.
    }
  }

  return trail;
}
