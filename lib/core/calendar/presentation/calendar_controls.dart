import 'package:flutter/material.dart';

import 'calendar_palette.dart';

/// 自绘按钮：不用 Material 的 IconButton / InkWell，按压有轻微缩放与底色。
class CalendarIconButton extends StatefulWidget {
  const CalendarIconButton({
    super.key,
    required this.icon,
    required this.palette,
    required this.onTap,
    this.tooltip,
    this.size = 44,
    this.iconSize = 22,
    this.angle = 0,
    this.radius = 14,
  });

  final IconData icon;
  final CalendarPalette palette;
  final VoidCallback onTap;
  final String? tooltip;
  final double size;
  final double iconSize;

  /// 图标旋转角（收起/展开的箭头朝向）。
  final double angle;

  /// 悬浮底色的圆角（页头小按钮 11，页面级按钮 14）。
  final double radius;

  @override
  State<CalendarIconButton> createState() => _CalendarIconButtonState();
}

class _CalendarIconButtonState extends State<CalendarIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.9 : 1,
        duration: const Duration(milliseconds: 110),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: _pressed
                ? widget.palette.accentSoft
                : Colors.transparent,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
          child: Transform.rotate(
            angle: widget.angle,
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: widget.palette.textPrimary,
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip == null) return button;
    return Tooltip(message: widget.tooltip!, child: button);
  }
}

/// 自绘胶囊开关。
class CalendarSwitch extends StatelessWidget {
  const CalendarSwitch({
    super.key,
    required this.value,
    required this.palette,
    required this.onChanged,
  });

  final bool value;
  final CalendarPalette palette;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 48,
        height: 28,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? palette.accent : palette.divider,
          borderRadius: BorderRadius.circular(16),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: palette.surface,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: palette.shadow,
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 自绘主按钮：圆角、按压缩放，避免默认 FilledButton 的 Material 观感。
class CalendarActionButton extends StatefulWidget {
  const CalendarActionButton({
    super.key,
    required this.label,
    required this.palette,
    required this.onTap,
    this.filled = true,
    this.icon,
    this.height = 48,
  });

  final String label;
  final CalendarPalette palette;
  final VoidCallback? onTap;
  final bool filled;
  final IconData? icon;
  final double height;

  @override
  State<CalendarActionButton> createState() => _CalendarActionButtonState();
}

class _CalendarActionButtonState extends State<CalendarActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final background = widget.filled
        ? (enabled ? widget.palette.accent : widget.palette.divider)
        : Colors.transparent;
    final foreground = widget.filled
        ? (enabled ? Colors.white : widget.palette.textSecondary)
        : widget.palette.accent;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: widget.height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(16),
            border: widget.filled
                ? null
                : Border.all(color: widget.palette.accent),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 18, color: foreground),
                const SizedBox(width: 6),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 轻量自定义 toast，替代默认 SnackBar。
class CalendarToast {
  CalendarToast._();

  static OverlayEntry? _current;

  static void show(
    BuildContext context,
    String message,
    CalendarPalette palette,
  ) {
    _current?.remove();
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (context) {
        return Positioned(
          left: 24,
          right: 24,
          bottom: MediaQuery.of(context).padding.bottom + 96,
          child: IgnorePointer(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 10 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: BoxDecoration(
                  color: palette.textPrimary.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: palette.shadow,
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    _current = entry;
    overlay.insert(entry);
    Future<void>.delayed(const Duration(milliseconds: 2200), () {
      if (_current == entry) {
        entry.remove();
        _current = null;
      }
    });
  }
}
