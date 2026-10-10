// 可配置快捷底栏：前 N−1 为钉选入口，末位固定 ⋯。
// iOS 手感：毛玻璃条 + 弹簧胶囊指示器 + 按压缩放。

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

  @override
  State<QuickNavBottomBar> createState() => _QuickNavBottomBarState();
}

class _QuickNavBottomBarState extends State<QuickNavBottomBar>
    with SingleTickerProviderStateMixin {
  static const double _barH = 64;
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
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final n = _slotCount;

    return SizedBox(
      height: _barH + bottomInset + 16,
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
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
                            for (var i = 0; i < widget.visibleEntries.length; i++)
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
                                    widget.onSelect(widget.visibleEntries[i].id);
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
      child: AnimatedScale(
        scale: 1,
        duration: const Duration(milliseconds: 120),
        child: SizedBox(
          height: 64,
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
      ),
    );
  }
}
