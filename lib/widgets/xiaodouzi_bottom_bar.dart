import 'dart:math' show exp, cos;

import 'package:flutter/material.dart';

/// 弹跳曲线 — 指数衰减余弦震荡，比 elasticOut 更弹
class _QQCurve extends Curve {
  const _QQCurve();

  @override
  double transform(double t) {
    return 1 - exp(-4.5 * t) * cos(15.708 * t);
  }
}

class XiaoDouZiBottomBar extends StatefulWidget {
  final int currentIndex;
  final Function(int) onItemSelected;
  final VoidCallback? onAddPressed;

  const XiaoDouZiBottomBar({
    super.key,
    required this.currentIndex,
    required this.onItemSelected,
    this.onAddPressed,
  });

  @override
  State<XiaoDouZiBottomBar> createState() => _XiaoDouZiBottomBarState();
}

class _XiaoDouZiBottomBarState extends State<XiaoDouZiBottomBar>
    with SingleTickerProviderStateMixin {
  static const double _barWidth = 328;
  static const double _barHeight = 64;
  static const double _capsuleW = 90;
  static const double _capsuleH = 50;

  static const List<IconData> _icons = [
    Icons.dashboard_outlined,
    Icons.chat_bubble_outline,
    Icons.timer_outlined,
  ];

  static const List<IconData> _activeIcons = [
    Icons.dashboard,
    Icons.chat_bubble,
    Icons.timer,
  ];

  late final AnimationController _ctrl;
  late final CurvedAnimation _curve;
  int _prev = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _curve = CurvedAnimation(
      parent: _ctrl,
      curve: const _QQCurve(),
    );
  }

  @override
  void didUpdateWidget(XiaoDouZiBottomBar old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      _prev = old.currentIndex;
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final primaryColor = cs.primary;
    final inactiveColor = primaryColor.withValues(alpha: 0.4);
    final itemW = _barWidth / _icons.length;

    double capsuleLeft(int idx) => idx * itemW + (itemW - _capsuleW) / 2;

    final bottomInset = MediaQuery.of(context).padding.bottom;
    return SizedBox(
      height: _barHeight + bottomInset + 20,
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: _barWidth,
          height: _barHeight,
          child: Stack(
            children: [
              // 背景（与菜单卡片完全一致）
              Card(
                elevation: 2,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_barHeight / 2),
                ),
                child: SizedBox(width: _barWidth, height: _barHeight),
              ),
              // 滑动胶囊指示器
              AnimatedBuilder(
                animation: _curve,
                builder: (context, _) {
                  final t = _curve.value;
                  final from = capsuleLeft(_prev);
                  final to = capsuleLeft(widget.currentIndex);
                  final left = (from + (to - from) * t).clamp(0.0, _barWidth - _capsuleW);
                  return Padding(
                    padding: EdgeInsets.fromLTRB(left, (_barHeight - _capsuleH) / 2, 0, 0),
                    child: Container(
                      width: _capsuleW,
                      height: _capsuleH,
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(_capsuleH / 2),
                      ),
                    ),
                  );
                },
              ),
              // Tab items
              Positioned.fill(
                child: Row(
                  children: List.generate(_icons.length, (i) {
                    final isActive = widget.currentIndex == i;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => widget.onItemSelected(i),
                        behavior: HitTestBehavior.opaque,
                        child: SizedBox(
                          height: _barHeight,
                          child: Center(
                            child: Icon(
                              isActive ? _activeIcons[i] : _icons[i],
                              size: 22,
                              color: isActive ? primaryColor : inactiveColor,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
