import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'calendar_palette.dart';

/// 胶囊导航（年 / 月 / 周 / 日 / 日程）。
///
/// 指示条由页签弹簧进度 [progress]（0..4 的连续值）驱动：位置插值 +
/// 高速拉伸（scaleX ≤ 1.14，体积守恒），落定回弹。
class CalendarCapsuleNav extends StatefulWidget {
  const CalendarCapsuleNav({
    super.key,
    required this.tabs,
    required this.activeIndex,
    required this.progress,
    required this.onTap,
    required this.palette,
  });

  final List<String> tabs;
  final int activeIndex;
  final ValueListenable<double> progress;
  final ValueChanged<int> onTap;
  final CalendarPalette palette;

  @override
  State<CalendarCapsuleNav> createState() => _CalendarCapsuleNavState();
}

class _CalendarCapsuleNavState extends State<CalendarCapsuleNav> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: ValueListenableBuilder<double>(
        valueListenable: widget.progress,
        builder: (context, t, _) {
          final stretch =
              1 + 0.14 * math.min(1.0, (t - widget.activeIndex).abs());
          return LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              const pad = 3.0;
              final buttonWidth = (width - pad * 2) / widget.tabs.length;
              return Container(
                height: 44,
                decoration: BoxDecoration(
                  color: widget.palette.surfaceAlt,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: widget.palette.divider),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: pad,
                      left: pad,
                      width: buttonWidth,
                      height: 44 - pad * 2,
                      child: Center(
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.diagonal3Values(
                            stretch,
                            1 / stretch,
                            1,
                          ),
                          child: Container(
                            height: 38,
                            decoration: BoxDecoration(
                              color: widget.palette.surface,
                              borderRadius: BorderRadius.circular(19),
                              boxShadow: [
                                BoxShadow(
                                  color: widget.palette.shadow,
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Transform.translate(
                        offset: Offset(t * buttonWidth, 0),
                        child: Row(
                          children: [
                            for (var i = 0; i < widget.tabs.length; i++)
                              _NavButton(
                                label: widget.tabs[i],
                                active: i == widget.activeIndex,
                                width: buttonWidth,
                                palette: widget.palette,
                                onTap: () => widget.onTap(i),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _NavButton extends StatefulWidget {
  const _NavButton({
    required this.label,
    required this.active,
    required this.width,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool active;
  final double width;
  final CalendarPalette palette;
  final VoidCallback onTap;

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: SizedBox(
        width: widget.width,
        height: 38,
        child: Center(
          child: AnimatedScale(
            scale: _pressed ? 0.92 : 1,
            duration: const Duration(milliseconds: 130),
            curve: Curves.easeOutBack,
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              style: TextStyle(
                fontSize: 14,
                fontWeight: widget.active ? FontWeight.w600 : FontWeight.w500,
                color: widget.active
                    ? widget.palette.textPrimary
                    : widget.palette.textSecondary,
              ),
              child: Text(widget.label),
            ),
          ),
        ),
      ),
    );
  }
}
