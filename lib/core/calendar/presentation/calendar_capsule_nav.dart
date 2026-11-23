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
    this.velocity,
  });

  final List<String> tabs;
  final int activeIndex;
  final ValueListenable<double> progress;
  final ValueChanged<int> onTap;
  final CalendarPalette palette;

  /// 页签弹簧速度（槽/秒）。原型按速度驱动 pill 高速拉伸
  /// stretch = min(0.14, |v|*0.012)：起手加速变宽、落定回弹收窄。
  /// 缺省时退化为「进度差」近似（旧行为）。
  final ValueListenable<double>? velocity;

  @override
  State<CalendarCapsuleNav> createState() => _CalendarCapsuleNavState();
}

class _CalendarCapsuleNavState extends State<CalendarCapsuleNav> {
  /// 无速度源时用的常量 notifier（保持静止态 stretch=1）。
  static final ValueNotifier<double> _kVelocityFallback = ValueNotifier<double>(
    0,
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: ValueListenableBuilder<double>(
        valueListenable: widget.progress,
        builder: (context, t, _) {
          return ValueListenableBuilder<double>(
            valueListenable: widget.velocity ?? _kVelocityFallback,
            builder: (context, v, _) {
              // 原型：速度（槽/秒）→ stretch = min(0.14, |v|*0.012)。
              // 无速度源时退化为进度差近似（起手快、落定回弹）。
              final speed = widget.velocity == null
                  ? (t - widget.activeIndex).abs() * 60
                  : v.abs();
              final stretch = 1 + 0.14 * math.min(1.0, speed * 0.012 / 0.14);
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
                        // 指示 pill：随弹簧进度连续平移（t 即 0..4 的槽位坐标）。
                        Positioned(
                          top: pad,
                          left: pad + t.clamp(0.0, 4.0) * buttonWidth,
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
                        // 页签文字：原位铺满，不随 pill 平移。
                        Positioned.fill(
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
                      ],
                    ),
                  );
                },
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
              duration: const Duration(milliseconds: 170),
              // easeOut 收尾柔和：pill 是弹簧（ease-out 型收敛），文字
              // 若走默认 linear 会比 pill 晚变色且观感拖尾。
              curve: Curves.easeOut,
              // 显式带上主题字体族：AnimatedDefaultTextStyle 是 replace 语义，
              // 不带 fontFamily 会退回引擎默认字体（丢全局字体）。
              style: TextStyle(
                fontSize: 14,
                fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
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
