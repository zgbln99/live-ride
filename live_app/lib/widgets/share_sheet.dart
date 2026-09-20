import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../core/lr_theme.dart';
import '../i18n/strings.dart';
import 'lr_common.dart';

/// Arkusz udostępniania linku.
///
/// Trzy drogi, bo trzy różne sytuacje: systemowy arkusz (wysyłam komuś), kod
/// QR (pokazuję komuś obok, kto ma telefon w ręku) i kopiowanie (wklejam
/// gdziekolwiek). Kod QR rysuje się lokalnie — żaden generator obrazków nie
/// dostaje linku do prywatnej jazdy.
Future<void> showLrShareSheet(
  BuildContext context, {
  required String title,
  required String url,
  required String message,
  String? subtitle,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _ShareSheet(
      title: title,
      subtitle: subtitle,
      url: url,
      message: message,
    ),
  );
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({
    required this.title,
    required this.url,
    required this.message,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final String url;
  final String message;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  bool _showQr = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Zagnieżdżony arkusz zamyka sam siebie i wraca tam, skąd
            // został otwarty — nigdy dalej.
            Row(
              children: [
                Expanded(child: Text(widget.title, style: LR.fieldValue(18))),
                const LrSheetClose(),
              ],
            ),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                widget.subtitle!,
                style: LR.body.copyWith(fontSize: 12.5, height: 1.45),
              ),
            ],
            const SizedBox(height: 16),

            if (_showQr) ...[
              Center(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: QrImageView(
                    data: widget.url,
                    size: 220,
                    version: QrVersions.auto,
                    backgroundColor: Colors.white,
                    // Środkowy poziom korekcji: kod ma się zeskanować także
                    // z ekranu przez cudzą, brudną szybkę aparatu.
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            LrPanel(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Text(
                widget.url,
                style: LR.body.copyWith(fontSize: 12.5, height: 1.4),
              ),
            ),
            const SizedBox(height: 14),

            FilledButton.icon(
              icon: const Icon(Icons.ios_share, size: 18),
              label: Text(S.shareTheLink),
              onPressed: () => SharePlus.instance.share(
                ShareParams(text: widget.message, subject: widget.title),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 18),
                    label: Text(S.copyLink),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: widget.url));
                      if (context.mounted) showLrMessage(context, S.linkCopied);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(
                      _showQr ? Icons.qr_code_2_outlined : Icons.qr_code_2,
                      size: 18,
                    ),
                    label: Text(_showQr ? S.hideQr : S.showQr),
                    onPressed: () => setState(() => _showQr = !_showQr),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
