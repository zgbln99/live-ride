import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/api_client.dart';
import '../core/lr_theme.dart';
import '../services/app_services.dart';
import '../widgets/lr_common.dart';

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
                  const LrStatusChip(
                    label: 'BROADCASTING',
                    color: LR.alert,
                    filled: true,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (session == null) ...[
              Text(
                'Share your position, speed, distance and heart rate with '
                'anyone holding the link. Spectators need no account.',
                style: LR.body.copyWith(height: 1.45),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _busy ? null : _start,
                icon: const Icon(Icons.sensors, size: 18),
                label: const Text('START LIVE'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : _join,
                icon: const Icon(Icons.group_add_outlined, size: 18),
                label: const Text('JOIN WITH A CODE'),
              ),
            ] else ...[
              _row('RIDER', widget.services.profile.riderName),
              const SizedBox(height: 12),
              _copyRow('JOIN CODE', session.joinToken),
              const SizedBox(height: 12),
              _copyRow('SPECTATOR LINK', live.viewerUrl ?? ''),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => SharePlus.instance.share(
                  ShareParams(
                    text: live.viewerUrl ?? '',
                    subject: 'Follow my ride on Live Ride',
                  ),
                ),
                icon: const Icon(Icons.ios_share, size: 18),
                label: const Text('SHARE THE LINK'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : _stop,
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                label: const Text('END LIVE'),
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
          tooltip: 'Copy',
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
        title: const Text('Join a LIVE ride'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'LIVE code'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Join'),
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
