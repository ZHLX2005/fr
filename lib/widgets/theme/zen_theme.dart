import 'package:flutter/material.dart';

class ZenColors {
  static const bg = Color(0xFFF4F1EA);
  static const ink = Color(0xFF2C2C2C);
  static const hair = Color(0xFFD9D5C8);
  static const secondary = Color(0xFF8A8475);
  static const sage = Color(0xFF7A9A7E);
  static const mutedRed = Color(0xFFA0594A);
  static const surface = Color(0xFFFBF8F1);
}

class ZenText {
  static const body = TextStyle(
    fontFamily:
        '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
    fontSize: 16,
    color: ZenColors.ink,
    height: 1.3,
  );
  static const label = TextStyle(
    fontFamily:
        '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
    fontSize: 13,
    color: ZenColors.secondary,
  );
  static const title = TextStyle(
    fontFamily:
        '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: ZenColors.ink,
  );
  static const button = TextStyle(
    fontFamily:
        '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
    fontSize: 16,
    fontWeight: FontWeight.w500,
  );
  static const monoDigit = TextStyle(
    fontFamily: 'SF Mono, Menlo, Consolas, monospace',
    fontSize: 40,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
    color: ZenColors.ink,
  );
  static const monoDigitLarge = TextStyle(
    fontFamily: 'SF Mono, Menlo, Consolas, monospace',
    fontSize: 64,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
    color: ZenColors.ink,
  );
  static const monoDigitSmall = TextStyle(
    fontFamily: 'SF Mono, Menlo, Consolas, monospace',
    fontSize: 14,
    fontFeatures: [FontFeature.tabularFigures()],
    color: ZenColors.secondary,
  );
}

BoxDecoration zenCard({Color? color}) => BoxDecoration(
      color: color ?? ZenColors.surface,
      border: Border.all(color: ZenColors.hair, width: 1),
      borderRadius: BorderRadius.circular(6),
    );

BoxDecoration zenDottedZone() => BoxDecoration(
      color: ZenColors.surface,
      border: Border.all(color: ZenColors.hair, width: 1, style: BorderStyle.solid),
      borderRadius: BorderRadius.circular(6),
    );

ButtonStyle zenButton({Color? foreground, Color? border, Color? background}) =>
    OutlinedButton.styleFrom(
      foregroundColor: foreground ?? ZenColors.ink,
      side: BorderSide(color: border ?? ZenColors.hair),
      backgroundColor: background,
      minimumSize: const Size(88, 44),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      textStyle: ZenText.button,
    );

// =====================================================================
// Composite widgets — the zen theme is "not just colors, but a UI".
// =====================================================================

/// Section card with a small label header. The canonical "stat / setting"
/// container used by clocks dashboard, metronome's accent legend, and any
/// new page that needs a labelled panel.
///
/// Defaults: 12px padding, 8px gap between title and content.
class ZenSection extends StatelessWidget {
  const ZenSection({
    super.key,
    required this.title,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.gap = 8,
  });

  final String title;
  final Widget child;
  final EdgeInsets padding;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: zenCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: ZenText.label),
          SizedBox(height: gap),
          child,
        ],
      ),
    );
  }
}

/// Circular icon control button. Three flavors via [variant]:
///   • `ZenIconButtonVariant.tint`   — 44×44 with color@10% bg (clocks, runner).
///   • `ZenIconButtonVariant.outline` — 48×48 with surface bg + hair border (BPM ±).
///   • `ZenIconButtonVariant.hero`   — 80×80 solid sage + glow (play / stop).
///
/// Icon color and bg follow the flavor; override via [color] / [background].
class ZenIconButton extends StatelessWidget {
  const ZenIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.color = ZenColors.sage,
    this.background,
    this.size = 44,
    this.iconSize = 24,
    this.variant = ZenIconButtonVariant.tint,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  final Color? background;
  final double size;
  final double iconSize;
  final ZenIconButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (variant) {
      ZenIconButtonVariant.tint => (
        color.withValues(alpha: 0.1),
        color,
      ),
      ZenIconButtonVariant.outline => (
        ZenColors.surface,
        color,
      ),
      ZenIconButtonVariant.hero => (
        ZenColors.sage,
        Colors.white,
      ),
    };
    final decoration = switch (variant) {
      ZenIconButtonVariant.outline => BoxDecoration(
          color: background ?? bg,
          shape: BoxShape.circle,
          border: Border.all(color: ZenColors.hair, width: 1),
        ),
      ZenIconButtonVariant.hero => BoxDecoration(
          color: ZenColors.sage,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: ZenColors.sage.withValues(alpha: 0.4),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
      _ => BoxDecoration(
          color: background ?? bg,
          shape: BoxShape.circle,
        ),
    };
    final effectiveIconSize =
        variant == ZenIconButtonVariant.hero ? 48.0 : iconSize;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: decoration,
        child: Icon(icon, color: fg, size: effectiveIconSize),
      ),
    );
  }
}

enum ZenIconButtonVariant { tint, outline, hero }

/// 12×12 status dot. The default style matches the clock beat dot:
/// active = filled sage + sage border, inactive = transparent + secondary border.
///
/// For legend swatches (solid color, no state), pass `color` and leave
/// `active = false` — the dot renders as a solid color circle.
class ZenDot extends StatelessWidget {
  const ZenDot({
    super.key,
    this.active = false,
    this.color = ZenColors.sage,
    this.inactiveBorder = ZenColors.secondary,
    this.size = 12,
  });

  final bool active;
  final Color color;
  final Color inactiveBorder;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: active ? color : Colors.transparent,
        border: Border.all(color: active ? color : inactiveBorder),
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Centered empty state: hair-tinted icon + label, optional action button.
///
/// Used by Clocks ("No clocks yet") and Tracks ("No tracks yet").
class ZenEmptyState extends StatelessWidget {
  const ZenEmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.actionColor = ZenColors.sage,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color actionColor;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: ZenColors.hair),
          const SizedBox(height: 16),
          Text(message, style: ZenText.label),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: onAction,
              style: zenButton(foreground: actionColor, border: actionColor),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Swipe-action button (80px wide, icon + label, solid color bg).
///
/// Used inside [_RecordTile] for "Delete" / "Create". [leftRounded] tucks
/// the leftmost action under the card's right rounded edge.
class ZenSwipeAction extends StatelessWidget {
  const ZenSwipeAction({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.leftRounded = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool leftRounded;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 80,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: leftRounded
              ? const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  bottomLeft: Radius.circular(6),
                )
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// Formatters — collapse 5+ duplicate copies into one canonical version.
// =====================================================================

/// Human-friendly duration: `'1h 23m 45s'`, `'23m 45s'`, or `'45s'`.
///
/// Picks the most informative unit and drops the lower ones only when the
/// higher unit is zero. Zero seconds renders as `'0s'`.
String formatDuration(int seconds) {
  if (seconds <= 0) return '0s';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) return '${h}h ${m}m ${s}s';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}

/// Clock-style time: `HH:MM:SS` (zero-padded) when ≥1h, else `MM:SS`.
/// Negative values get a leading `-`.
String formatTime(int seconds) {
  final isNegative = seconds < 0;
  final absSeconds = seconds.abs();
  final h = absSeconds ~/ 3600;
  final m = (absSeconds % 3600) ~/ 60;
  final s = absSeconds % 60;
  final sign = isNegative ? '-' : '';
  if (h > 0) {
    return '$sign${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }
  return '$sign${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

// =====================================================================
// Page-level helpers — Scaffold shell + confirm dialog.
// =====================================================================

/// Standard zen page chrome: bg-tinted Scaffold, flat AppBar with title in
/// [ZenText.title], optional actions / FAB / bottom nav.
///
/// Used by every page (clock_demo, metronome_demo, track_editor_page,
/// track_records_page, track_runner_page).
Scaffold zenPageScaffold({
  required String title,
  required Widget body,
  List<Widget>? actions,
  Widget? fab,
  Widget? bottomNavigationBar,
  Color? backgroundColor,
  Widget? leading,
}) {
  return Scaffold(
    backgroundColor: backgroundColor ?? ZenColors.bg,
    appBar: AppBar(
      backgroundColor: ZenColors.bg,
      elevation: 0,
      title: Text(title, style: ZenText.title),
      actions: actions,
      leading: leading,
    ),
    body: body,
    floatingActionButton: fab,
    bottomNavigationBar: bottomNavigationBar,
  );
}

/// Destructive confirm dialog. Returns `true` if user confirmed.
///
/// Centralizes the Cancel + muted-red-confirm pattern used by 5+ call sites
/// (delete clock, delete track, clear records, wipe-all, rename record).
class ZenConfirmDialog {
  const ZenConfirmDialog._();

  static Future<bool> show({
    required BuildContext context,
    required String title,
    required String message,
    required VoidCallback onConfirm,
    String confirmLabel = 'Delete',
    String cancelLabel = 'Cancel',
    Color confirmColor = ZenColors.mutedRed,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel),
          ),
          TextButton(
            onPressed: () {
              onConfirm();
              Navigator.pop(ctx, true);
            },
            child: Text(confirmLabel, style: TextStyle(color: confirmColor)),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
