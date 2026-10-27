// 可配置快捷底栏：前 N−1 为钉选入口，末位为 ⋯ 或设置直连入口。
// iOS 手感：毛玻璃胶囊外壳 + 弹簧指示器 + 按压缩放。
// 主壳用 Stack 浮层挂载（勿用 Scaffold.bottomNavigationBar，避免矩形槽位铺底色）。

import 'dart:math' show exp, cos;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../nav/nav_entry.dart';
import 'nav_entry_icon.dart';

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
    this.lastSlotEntry,
    required this.selectedId,
    required this.moreSelected,
    required this.onSelect,
    required this.onMore,
  });

  /// 底栏可视高度（不含系统 safe-area）。
  static const double barHeight = 64;

  /// 底栏下方额外空隙（与总占位 `barHeight + 16 + bottomInset` 一致）。
  static const double barBottomGap = 16;

  final List<NavEntry> visibleEntries;

  /// 末位槽直连入口（设置）。非 null 时末位槽渲染它并走 [onSelect]，
  /// 为 null 时末位槽保持 ⋯ 并走 [onMore]。
  final NavEntry? lastSlotEntry;
  final String? selectedId;
  final bool moreSelected;
  final ValueChanged<String> onSelect;
  final VoidCallback onMore;

  /// 浮层底栏占位（含系统底 inset）。给滚动区 padding.bottom 用；
  /// 勿写入 MediaQuery.padding（SafeArea 会吃掉并露出 Scaffold 色条）。
  static double bodyBottomReserve(BuildContext context) =>
      barHeight + barBottomGap + MediaQuery.paddingOf(context).bottom;

  @override
  State<QuickNavBottomBar> createState() => _QuickNavBottomBarState();
}
class _QuickNavBottomBarState extends State<QuickNavBottomBar>
    with SingleTickerProviderStateMixin {
  static const double _barH = QuickNavBottomBar.barHeight;
  static const double _capsuleH = 48;

  late final AnimationController _ctrl;
  late final CurvedAnimation _curve;
  int _prev = 0;
  int _current = 0;

  int get _slotCount => widget.visibleEntries.length + 1; // + ⋯

  int _indexOfSelection() {
    final last = widget.lastSlotEntry;
    if (last != null && widget.selectedId == last.id) {
      return widget.visibleEntries.length;
    }
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

  /// 末位槽：设置直连入口（lastSlotEntry 非 null）或 ⋯ 溢出。
  Widget _buildLastSlot(ColorScheme cs) {
    final last = widget.lastSlotEntry;
    if (last != null) {
      return _NavTab(
        entry: last,
        icon: last.icon,
        label: last.title,
        selected: widget.selectedId == last.id,
        color: cs.primary,
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onSelect(last.id);
        },
      );
    }
    return _NavTab(
      icon: Icons.more_horiz_rounded,
      label: '更多',
      selected: widget.moreSelected,
      color: cs.primary,
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onMore();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final n = _slotCount;

    return SizedBox(
      height: _barH + bottomInset + QuickNavBottomBar.barBottomGap,
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          // 胶囊外壳本身；外层 SizedBox 无背景，避免矩形父容器铺色。
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_barH / 2),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Container(
                height: _barH,
                decoration: BoxDecoration(
                  color: cs.surface.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(_barH / 2),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.35),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final itemW = constraints.maxWidth / n;
                    // 下限 48：5 槽窄屏（≤336dp）单槽不足 56，钳到 56 会渗进邻槽。
                    final capsuleW = (itemW - 8).clamp(48.0, 88.0);

                    double leftOf(int idx) =>
                        idx * itemW + (itemW - capsuleW) / 2;

                    return ClipRect(
                      child: Stack(
                      children: [
                        AnimatedBuilder(
                          animation: _curve,
                          builder: (context, _) {
                            final t = _curve.isDismissed ? 1.0 : _curve.value;
                            final left = leftOf(_prev) +
                                (leftOf(_current) - leftOf(_prev)) * t;
                            return Positioned(
                              left: left,
                              top: (_barH - _capsuleH) / 2,
                              child: Container(
                                width: capsuleW,
                                height: _capsuleH,
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: 0.14),
                                  borderRadius:
                                      BorderRadius.circular(_capsuleH / 2),
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
                                  entry: widget.visibleEntries[i],
                                  icon: widget.visibleEntries[i].icon,
                                  label: widget.visibleEntries[i].title,
                                  selected: !widget.moreSelected &&
                                      widget.selectedId ==
                                          widget.visibleEntries[i].id,
                                  color: cs.primary,
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    widget
                                        .onSelect(widget.visibleEntries[i].id);
                                  },
                                ),
                              ),
                            Expanded(child: _buildLastSlot(cs)),
                          ],
                        ),
                      ],
                    ),
                    );
                  },
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
    this.entry,
  });

  static const double _barH = QuickNavBottomBar.barHeight;

  /// 非 null 时优先渲染 demo 专属 SVG（单色随 [color] 选中态着色）；
  /// [icon] 作为无 SVG 时的兜底（核心入口 / ⋯）。
  final NavEntry? entry;
  final IconData icon;
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  Widget _icon(Color c) {
    final e = entry;
    if (e != null) {
      return NavEntryIcon(entry: e, size: 18, tint: c);
    }
    return Icon(icon, size: 18, color: c);
  }

  @override
  Widget build(BuildContext context) {
    final c = selected ? color : color.withValues(alpha: 0.42);
    // 真机中文 ascent/descent 易撑破固定高 → 黄黑 overflow。
    // 用固定文字槽 + ClipRect，禁止任何溢出绘制。
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: _barH,
        width: double.infinity,
        child: ClipRect(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 18,
                  child: Center(child: _icon(c)),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  height: 12,
                  child: Center(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9,
                        height: 1.0,
                        leadingDistribution: TextLeadingDistribution.even,
                        fontWeight: FontWeight.w700,
                        color: c,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 浮层快捷底栏显隐开关：子页面（Lab 上滑面板铺满、远程输入触摸板/全屏态）
/// 通过登记**自己的 nav id** 请求隐藏，MainScreen 只在「请求方 == 当前选中页」
/// 时才把底栏撤掉。
///
/// 设计要点：
/// - **值必须是 nav id 而不是裸 bool**：IndexedStack 里所有钉选页同时存活
///   （State 常驻），裸 bool 会让离场页面的请求泄漏到别的页——远程输入钉在
///   首位后全局看不见底栏，就是这个坑。
/// - 后写覆盖先写；页面离场（dispose）或退出请求态时清回 null。
class _BottomBarVisibility extends Notifier<String?> {
  @override
  String? build() => null;

  void setHidden(String? navId) {
    if (state == navId) return;
    state = navId;
  }
}

final bottomBarVisibilityProvider =
    NotifierProvider<_BottomBarVisibility, String?>(_BottomBarVisibility.new);
