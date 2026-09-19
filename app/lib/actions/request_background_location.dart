import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wanderer/i18n/app_localizations.dart';
import 'package:wanderer/provider/local_settings_provider.dart';

String _liveRideBrand(String text) => text
    .replaceAll('Wanderer', 'Live Ride')
    .replaceAll('wanderer', 'Live Ride');

/// Offers to upgrade a `whileInUse` grant to background ("Allow all the time")
/// before a tracking session starts.
Future<LocationPermission> requestBackgroundLocation(
  BuildContext context,
  WidgetRef ref,
  LocationPermission permission,
) async {
  if (permission != LocationPermission.whileInUse) return permission;

  if (Platform.isIOS) return Geolocator.requestPermission();
  if (!Platform.isAndroid) return permission;

  if (ref.read(localSettingsProvider).backgroundLocationAsked) {
    return permission;
  }

  final l10n = AppLocalizations.of(context)!;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(_liveRideBrand(l10n.background_location_title)),
      content: Text(_liveRideBrand(l10n.background_location_body)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.not_now),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.background_location_confirm),
        ),
      ],
    ),
  );

  await ref
      .read(localSettingsProvider.notifier)
      .markBackgroundLocationAsked();

  if (accepted != true) return permission;

  await Geolocator.openAppSettings();
  return permission;
}
