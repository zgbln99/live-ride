import 'dart:async';

import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../models/live_privacy.dart';
import '../services/app_services.dart';
import '../widgets/lr_common.dart';

/// Jazda grupowa: kto co widzi, punkt zbiórki i szybkie wiadomości.
Future<void> showGroupRideSheet(BuildContext context, AppServices services) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, controller) =>
          _GroupRideSheet(services: services, scrollController: controller),
    ),
  );
}

class _GroupRideSheet extends StatefulWidget {
  const _GroupRideSheet({
    required this.services,
    required this.scrollController,
  });

  final AppServices services;
  final ScrollController scrollController;

  @override
  State<_GroupRideSheet> createState() => _GroupRideSheetState();
}

class _GroupRideSheetState extends State<_GroupRideSheet> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    unawaited(widget.services.live.refreshMessages(force: true));
    _poll = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(widget.services.live.refreshMessages()),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.services.live;

    return AnimatedBuilder(
      animation: live,
      builder: (context, _) {
        final privacy = live.privacy;

        return ListView(
          controller: widget.scrollController,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            LrSectionHeader(
              title: S.whatOthersSee,
              padding: const EdgeInsets.only(bottom: 6),
            ),
            Text(
              S.privacyExplainer,
              style: LR.body.copyWith(fontSize: 12.5, height: 1.45),
            ),
            const SizedBox(height: 6),
            _privacyTile(
              title: S.sharePosition,
              value: privacy.sharePosition,
              onChanged: (value) =>
                  live.updatePrivacy(privacy.copyWith(sharePosition: value)),
            ),
            _privacyTile(
              title: S.shareSpeed,
              value: privacy.shareSpeed,
              onChanged: (value) =>
                  live.updatePrivacy(privacy.copyWith(shareSpeed: value)),
            ),
            _privacyTile(
              title: S.shareHeartRate,
              value: privacy.shareHeartRate,
              onChanged: (value) =>
                  live.updatePrivacy(privacy.copyWith(shareHeartRate: value)),
            ),
            _privacyTile(
              title: S.sharePower,
              value: privacy.sharePower,
              onChanged: (value) =>
                  live.updatePrivacy(privacy.copyWith(sharePower: value)),
            ),
            _privacyTile(
              title: S.shareBattery,
              value: privacy.shareBattery,
              onChanged: (value) =>
                  live.updatePrivacy(privacy.copyWith(shareBattery: value)),
            ),
            if (!privacy.sharesAnything)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  S.sharesNothing,
                  style: LR.body.copyWith(fontSize: 12, color: LR.alert),
                ),
              ),

            if (live.isActive) ...[
              const SizedBox(height: 20),
              LrSectionHeader(
                title: S.meetupPoint,
                padding: const EdgeInsets.only(bottom: 6),
              ),
              if (live.meetup == null)
                Text(S.meetupHint, style: LR.body.copyWith(fontSize: 12.5))
              else
                Text(
                  live.meetupLabel.isEmpty
                      ? '${live.meetup!.lat.toStringAsFixed(4)}, '
                            '${live.meetup!.lon.toStringAsFixed(4)}'
                      : live.meetupLabel,
                  style: LR.fieldValue(15),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.place_outlined, size: 18),
                      label: Text(S.meetupHere),
                      onPressed: _setMeetupHere,
                    ),
                  ),
                  if (live.meetup != null) ...[
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: () => live.setMeetup(),
                      child: Text(S.delete),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 20),
              LrSectionHeader(
                title: S.quickMessages,
                padding: const EdgeInsets.only(bottom: 6),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final message in QuickMessage.values)
                    ActionChip(
                      label: Text(message.body),
                      onPressed: () => live.sendMessage(message.body),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (live.messages.isEmpty)
                Text(S.noMessagesYet, style: LR.body)
              else
                LrPanel(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < live.messages.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          dense: true,
                          title: Text(
                            live.messages[i].body,
                            style: LR.fieldValue(14),
                          ),
                          subtitle: Text(
                            '${live.messages[i].author} · '
                            '${Fmt.clock(live.messages[i].sentAt)}',
                            style: LR.body.copyWith(fontSize: 11.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _privacyTile({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    title: Text(title),
    value: value,
    onChanged: onChanged,
  );

  Future<void> _setMeetupHere() async {
    final services = widget.services;
    final position =
        services.recorder.position ?? await services.location.lastKnown();
    if (position == null) {
      if (mounted) showLrMessage(context, S.noGpsPosition, error: true);
      return;
    }
    await services.live.setMeetup(point: position, label: S.meetupHere);
  }
}
