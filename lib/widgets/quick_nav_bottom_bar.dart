// 可配置快捷底栏：前 N−1 为钉选入口，末位固定 ⋯。
// iOS 液态玻璃近似：透明底 + 强 BackdropFilter + 高光描边（非 iOS 26 原生折射）。

import 'dart:math' show exp, cos;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/nav/nav_entry.dart';

class _IosSpringCurve extends Curve {
  const _IosSpringCurve();

  @override
  double transform(double t) {
    // 轻阻尼弹簧，接近 iOS tab 切换
    return 1 - exp(-5.2 * t) * cos(7.5 * t);
  }
}

class QuickNavBottomBar extends StatefulWidget {
  const QuickNavBottomBar({
    super.key,
    required this.visibleEntries,
    required this.selectedId,
    required this.moreSelected,
    required this.onSelect,
    required this.onMore,
  });

  final List<NavEntry> visibleEntries;
  final String? selectedId;
  final bool moreSelected;
  final ValueChanged<String> onSelect;
  final VoidCallback onMore;

  /// 胶囊本体高度（不含安全区与外边距）。
  static const double barHeight = 64;

  /// 胶囊下方到屏幕底的额外空隙（不含系统 inset）。
  static const double bottomGap = 16;

  /// Scaffold.extendBody 时，给页面预留的底栏占位（含安全区）。
  static double reserveHeight(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).bottom;
    return barHeight + bottomGap + inset;
  }

  @override
  State<QuickNavBottomBar> createState() => _QuickNavBottomBarState();
}

class _QuickNavBottomBarState extends State<QuickNavBottomBar>
    with SingleTickerProviderStateMixin {
  static const double _capsuleH = 48;

  late final AnimationController _ctrl;
  late final CurvedAnimation _curve;
  int _prev = 0;
  int _current = 0;

  int get _slotCount => widget.visibleEntries.length + 1; // + ⋯

  int _indexOfSelection() {
    if (widget.moreSelected) return widget.visibleEntries.length;
    final i = widget.visibleEntries.indexWhere((e) => e.id == widget.selectedId);
    return i < 0 ? 0 : i;
  }

  @override
  void initState() {
    super.initState();
    _current = _indexOfSelection();
    _prev = _current;
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 380),
      vsync: this,
    );
    _curve = CurvedAnimation(parent: _ctrl, curve: const _IosSpringCurve());
  }

  @override
  void didUpdateWidget(covariant QuickNavBottomBar old) {
    super.didUpdateWidget(old);
    final next = _indexOfSelection();
    if (next != _current) {
      _prev = _current;
      _current = next;
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final n = _slotCount;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final blurSigma = reduceMotion ? 0.0 : 28.0;

    // 浅色偏白、深色偏深的玻璃 tint —— 保持很低不透明度，让背后内容透出来
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glassFill = (isDark ? cs.surface : Colors.white)
        .withValues(alpha: isDark ? 0.22 : 0.28);
    final glassSheen = Colors.white.withValues(alpha: isDark ? 0.08 : 0.42);
    final rim = Colors.white.withValues(alpha: isDark ? 0.18 : 0.55);
    final rimInner = cs.outlineVariant.withValues(alpha: isDark ? 0.25 : 0.2);

    return SizedBox(
      height: QuickNavBottomBar.barHeight + bottomInset + QuickNavBottomBar.bottomGap,
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.circular(QuickNavBottomBar.barHeight / 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius:
                  BorderRadius.circular(QuickNavBottomBar.barHeight / 2),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                child: Container(
                  height: QuickNavBottomBar.barHeight,
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(QuickNavBottomBar.barHeight / 2),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        glassSheen,
                        glassFill,
                        glassFill.withValues(alpha: glassFill.a * 0.85),
                      ],
                      stops: const [0.0, 0.35, 1.0],
                    ),
                    border: Border.all(color: rim, width: 0.8),
                  ),
                  foregroundDecoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(QuickNavBottomBar.barHeight / 2),
                    border: Border.all(color: rimInner, width: 0.5),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: isDark ? 0.14 : 0.28),
                        Colors.transparent,
                        Colors.white.withValues(alpha: isDark ? 0.04 : 0.08),
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final itemW = constraints.maxWidth / n;
                      final capsuleW = (itemW - 8).clamp(56.0, 88.0);

                      double leftOf(int idx) =>
                          idx * itemW + (itemW - capsuleW) / 2;

                      return Stack(
                        children: [
                          AnimatedBuilder(
                            animation: _curve,
                            builder: (context, _) {
                              final t = _curve.isDismissed ? 1.0 : _curve.value;
                              final left = leftOf(_prev) +
                                  (leftOf(_current) - leftOf(_prev)) * t;
                              return Positioned(
                                left: left,
                                top: (QuickNavBottomBar.barHeight - _capsuleH) /
                                    2,
                                child: Container(
                                  width: capsuleW,
                                  height: _capsuleH,
                                  decoration: BoxDecoration(
                                    color: cs.primary.withValues(alpha: 0.16),
                                    borderRadius:
                                        BorderRadius.circular(_capsuleH / 2),
                                    border: Border.all(
                                      color:
                                          cs.primary.withValues(alpha: 0.12),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: cs.primary
                                            .withValues(alpha: 0.08),
                                        blurRadius: 12,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                          Row(
                            children: [
                              for (var i = 0;
                                  i < widget.visibleEntries.length;
                                  i++)
                                Expanded(
                                  child: _NavTab(
                                    icon: widget.visibleEntries[i].icon,
                                    label: widget.visibleEntries[i].title,
                                    selected: !widget.moreSelected &&
                                        widget.selectedId ==
                                            widget.visibleEntries[i].id,
                                    color: cs.primary,
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      widget.onSelect(
                                          widget.visibleEntries[i].id);
                                    },
                                  ),
                                ),
                              Expanded(
                                child: _NavTab(
                                  icon: Icons.more_horiz_rounded,
                                  label: '更多',
                                  selected: widget.moreSelected,
                                  color: cs.primary,
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    widget.onMore();
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = selected ? color : color.withValues(alpha: 0.42);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: QuickNavBottomBar.barHeight,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: c),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: c,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
