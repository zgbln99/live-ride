import 'package:flutter/material.dart';

import '../core/lr_theme.dart';

/// The Live Ride mark: a forward chevron in the accent colour.
class LrBrandMark extends StatelessWidget {
  const LrBrandMark({super.key, this.size = 28, this.dark = false});

  final double size;
  final bool dark;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _BrandPainter(dark ? Colors.white : LR.ink)),
  );
}

class _BrandPainter extends CustomPainter {
  const _BrandPainter(this.foreground);

  final Color foreground;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final accent = Paint()..color = LR.accent;
    final ink = Paint()..color = foreground;

    final chevron = Path()
      ..moveTo(w * 0.06, h * 0.82)
      ..lineTo(w * 0.46, h * 0.1)
      ..lineTo(w * 0.62, h * 0.42)
      ..lineTo(w * 0.34, h * 0.42)
      ..close();
    canvas.drawPath(chevron, ink);

    final flash = Path()
      ..moveTo(w * 0.44, h * 0.9)
      ..lineTo(w * 0.94, h * 0.18)
      ..lineTo(w * 0.78, h * 0.9)
      ..close();
    canvas.drawPath(flash, accent);
  }

  @override
  bool shouldRepaint(_BrandPainter oldDelegate) =>
      oldDelegate.foreground != foreground;
}

/// The wordmark used in headers.
class LrWordmark extends StatelessWidget {
  const LrWordmark({super.key, this.dark = false, this.compact = false});

  final bool dark;
  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      LrBrandMark(size: compact ? 20 : 24, dark: dark),
      const SizedBox(width: 8),
      Text(
        'LIVE RIDE',
        style: TextStyle(
          fontSize: compact ? 12 : 14,
          fontWeight: FontWeight.w900,
          letterSpacing: 2.2,
          color: dark ? Colors.white : LR.ink,
        ),
      ),
    ],
  );
}

/// A flat instrument panel: white, hairline border, minimal radius.
class LrPanel extends StatelessWidget {
  const LrPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color = LR.surface,
    this.borderColor = LR.line,
    this.accentEdge = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color color;
  final Color borderColor;

  /// Draws the cyan rule down the leading edge used for primary items.
  final bool accentEdge;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        border: Border(
          top: BorderSide(color: borderColor),
          right: BorderSide(color: borderColor),
          bottom: BorderSide(color: borderColor),
          left: accentEdge
              ? const BorderSide(color: LR.accent, width: 3)
              : BorderSide(color: borderColor),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: onTap == null
          ? content
          : Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(6),
                child: content,
              ),
            ),
    );
  }
}

class LrSectionHeader extends StatelessWidget {
  const LrSectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(2, 0, 2, 10),
  });

  final String title;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      children: [
        Expanded(child: Text(title.toUpperCase(), style: LR.sectionTitle)),
        if (trailing != null) trailing!,
      ],
    ),
  );
}

/// Label + value + unit, the atom every summary screen is built from.
class LrStat extends StatelessWidget {
  const LrStat({
    super.key,
    required this.label,
    required this.value,
    this.unit = '',
    this.valueSize = 22,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  final String label;
  final String value;
  final String unit;
  final double valueSize;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: crossAxisAlignment,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label.toUpperCase(), style: LR.fieldLabel),
      const SizedBox(height: 7),
      Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LR.fieldValue(valueSize),
            ),
          ),
          if (unit.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(unit, style: LR.fieldUnit),
          ],
        ],
      ),
    ],
  );
}

/// The LIVE / RECORDING / PAUSED status marker.
class LrStatusChip extends StatelessWidget {
  const LrStatusChip({
    super.key,
    required this.label,
    required this.color,
    this.filled = false,
    this.pulse = false,
  });

  final String label;
  final Color color;
  final bool filled;
  final bool pulse;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: filled ? color : color.withValues(alpha: 0.10),
      border: Border.all(color: color, width: 1.2),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: filled ? Colors.white : color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.3,
            color: filled ? Colors.white : color,
          ),
        ),
      ],
    ),
  );
}

/// A square map control. Deliberately not a floating pill.
class LrMapButton extends StatelessWidget {
  const LrMapButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.active = false,
    this.size = 44,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: active ? LR.accent : LR.surface,
      borderRadius: BorderRadius.circular(5),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            border: Border.all(color: active ? LR.accentDeep : LR.lineStrong),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Icon(icon, size: 21, color: LR.ink),
        ),
      ),
    ),
  );
}

class LrEmptyState extends StatelessWidget {
  const LrEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 60),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: LR.lineStrong),
          const SizedBox(height: 18),
          Text(title, style: LR.title, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: LR.body.copyWith(height: 1.45),
          ),
          if (action != null) ...[const SizedBox(height: 22), action!],
        ],
      ),
    ),
  );
}

/// Rider avatar built from initials — no upload, no placeholder faces.
class LrAvatar extends StatelessWidget {
  const LrAvatar({super.key, required this.initials, this.size = 44});

  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: LR.ink,
      borderRadius: BorderRadius.circular(size * 0.22),
    ),
    child: Text(
      initials,
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w900,
        fontSize: size * 0.38,
        letterSpacing: 0.5,
      ),
    ),
  );
}

/// Shows a snack bar with a message that is already rider-readable.
void showLrMessage(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? LR.alert : LR.ink,
        duration: Duration(seconds: error ? 6 : 3),
      ),
    );
}
