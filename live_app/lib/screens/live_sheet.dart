import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/api_client.dart';
import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import '../services/app_services.dart';
import '../widgets/lr_common.dart';
import 'group_ride_sheet.dart';

/// Start, join, share or end a LIVE session.
///
/// The same sheet is used from the ride computer and from the LIVE tab so the
/// controls never disagree with each other.
Future<void> showLiveSheet(BuildContext context, AppServices services) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _LiveSheet(services: services),
  );
}

class _LiveSheet extends StatefulWidget {
  const _LiveSheet({required this.services});

  final AppServices services;

  @override
  State<_LiveSheet> createState() => _LiveSheetState();
}

class _LiveSheetState extends State<_LiveSheet> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final live = widget.services.live;
    final session = live.session;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const LrWordmark(compact: true),
                const Spacer(),
                if (session != null)
                  LrStatusChip(
                    label: S.broadcasting,
                    color: LR.alert,
                    filled: true,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (session == null) ...[
              Text(S.liveDescription, style: LR.body.copyWith(height: 1.45)),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _busy ? null : _start,
                icon: const Icon(Icons.sensors, size: 18),
                label: Text(S.startLive),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : _join,
                icon: const Icon(Icons.group_add_outlined, size: 18),
                label: Text(S.joinWithCode),
              ),
            ] else ...[
              _row(S.rider, widget.services.profile.riderName),
              const SizedBox(height: 12),
              _copyRow(S.joinCode, session.joinToken),
              const SizedBox(height: 12),
              _copyRow(S.spectatorLink, live.viewerUrl ?? ''),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.groups_outlined, size: 18),
                label: Text(S.groupRide),
                onPressed: () => showGroupRideSheet(context, widget.services),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => SharePlus.instance.share(
                  ShareParams(
                    text: live.viewerUrl ?? '',
                    subject: S.followMyRide,
                  ),
                ),
                icon: const Icon(Icons.ios_share, size: 18),
                label: Text(S.shareTheLink),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : _stop,
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                label: Text(S.endLive),
                style: OutlinedButton.styleFrom(
                  foregroundColor: LR.alert,
                  side: const BorderSide(color: LR.alert),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: LR.fieldLabel),
      const SizedBox(height: 5),
      Text(
        value,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    ],
  );

  Widget _copyRow(String label, String value) => LrPanel(
    padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
    child: Row(
      children: [
        Expanded(child: _row(label, value)),
        IconButton(
          tooltip: S.copy,
          icon: const Icon(Icons.copy, size: 18),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: value));
            if (mounted) showLrMessage(context, '$label copied');
          },
        ),
      ],
    ),
  );

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      await widget.services.live.create();
      if (mounted) setState(() {});
    } on ApiException catch (e) {
      if (mounted) showLrMessage(context, e.message, error: true);
    } catch (e) {
      if (mounted) showLrMessage(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.joinLiveTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(labelText: S.liveCode),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(S.joinWithCode),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.trim().isEmpty) return;

    setState(() => _busy = true);
    try {
      await widget.services.live.join(code);
      if (mounted) setState(() {});
    } on ApiException catch (e) {
      if (mounted) showLrMessage(context, e.message, error: true);
    } catch (e) {
      if (mounted) showLrMessage(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    setState(() => _busy = true);
    await widget.services.live.stop();
    if (mounted) setState(() => _busy = false);
  }
}
