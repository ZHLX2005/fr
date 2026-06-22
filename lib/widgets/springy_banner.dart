import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// 弹性 Banner — 顶部下拉时跟随手指放大下移，松手用欠阻尼弹簧回弹。
///
/// 用法：把原本 [SliverAppBar.flexibleSpace] background 中的 [GestureDetector] + 图层子
/// 树整体替换为 [SpringyBanner]。
///
/// 行为：
///   - 仅响应 overscroll 顶部下拉（`position.pixels < 0`），不干扰正常滚动。
///   - 抗阻曲线：iOS 橡皮筋，到达 [_kMaxStretch] (120 px) 时饱和。
///   - 峰值放大 [_kPeakScale] (1.0 → 1.15x)。
///   - 松手用 [SpringSimulation] 回弹，~1-2 次可见震荡，400-600 ms 落定。
class SpringyBanner extends StatefulWidget {
  const SpringyBanner({
    super.key,
    required this.imagePath,
    required this.fallback,
    required this.onTap,
  });

  /// 用户选定的本地图片路径。`null` 时使用 [fallback]。
  final String? imagePath;

  /// 无图片时显示的占位组件（通常是渐变背景 + "点击设置 Banner" 提示）。
  final Widget fallback;

  /// 点击 banner 时触发的回调（沿用原有的"裁剪/移除"底部菜单）。
  final VoidCallback onTap;

  @override
  State<SpringyBanner> createState() => _SpringyBannerState();
}

class _SpringyBannerState extends State<SpringyBanner>
    with SingleTickerProviderStateMixin {
  // ---------- 常量 ----------
  static const double _kMaxStretch = 120.0; // 抗阻饱和点（px）
  static const double _kPeakScale = 0.15; // 1.0 → 1.15x
  // 质量 1 + 刚度 320 + 阻尼比 0.6（欠阻尼），保证 1-2 次可见回弹。
  // damping 必须是 sqrt(stiffness * mass) 的倍数 → 不能用 const（sqrt 不是常量）。
  static final SpringDescription _kSpring = SpringDescription(
    mass: 1.0,
    stiffness: 320.0,
    damping: 0.6 * 2.0 * math.sqrt(320.0), // ≈ 21.54
  );

  // ---------- 状态 ----------
  late final AnimationController _spring;
  ScrollPosition? _position;

  @override
  void initState() {
    super.initState();
    _spring = AnimationController.unbounded(vsync: this);
  }

  void _attachToScrollable() {
    // 取最近的可滚动区域。ProfilePage 是顶层 CustomScrollView 路由，
    // 直接找到的就是它自己 —— 不需要 NotificationListener。
    final scrollable = Scrollable.maybeOf(context);
    _position = scrollable?.position;
    _position?.addListener(_onScrollPosition);
  }

  void _onScrollPosition() {
    final pos = _position;
    if (pos == null) return;

    // 释放动画进行中，用户重新下拉 —— 平滑接管
    if (_spring.isAnimating) {
      _spring.stop();
    }

    final overscrollRaw = (-pos.pixels).clamp(0.0, _kMaxStretch);
    // iOS 橡皮筋抗阻：overscroll / (1 + overscroll / max)
    final overscroll =
        overscrollRaw / (1.0 + overscrollRaw / _kMaxStretch);
    _spring.value = overscroll;
  }

  void _onScrollEnd(ScrollEndNotification _) {
    if (_spring.value == 0) return;
    _spring.animateWith(
      SpringSimulation(_kSpring, _spring.value, 0.0, 0.0),
    );
  }

  @override
  void dispose() {
    _position?.removeListener(_onScrollPosition);
    _spring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 在 build 里取 Scrollable：initState 时 context 尚未挂载子树。
    if (_position == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _attachToScrollable());
    }
    return NotificationListener<ScrollEndNotification>(
      onNotification: (n) {
        _onScrollEnd(n);
        return false;
      },
      child: AnimatedBuilder(
        animation: _spring,
        builder: (context, child) {
          final v = _spring.value;
          return Transform.translate(
            offset: Offset(0, v),
            child: Transform.scale(
              scale: 1.0 + (v / _kMaxStretch) * _kPeakScale,
              alignment: Alignment.topCenter,
              child: child,
            ),
          );
        },
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: widget.imagePath != null
              ? Image.file(
                  File(widget.imagePath!),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  errorBuilder: (_, _, _) => widget.fallback,
                )
              : widget.fallback,
        ),
      ),
    );
  }
}
