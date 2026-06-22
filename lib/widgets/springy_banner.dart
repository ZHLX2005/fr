import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// 按压弹性 Banner — 按住时图放大 1.06x，松手用欠阻尼弹簧回弹。
///
/// 用法：把原本 [SliverAppBar.flexibleSpace] background 中的 [GestureDetector] + 图层子
/// 树整体替换为 [SpringyBanner]。
///
/// 设计原因（避免与外层 list overscroll 冲突）：
///   原本想用"下拉 overscroll"驱动 spring，但 `BouncingScrollPhysics` + `SliverAppBar`
///   会让 list 整体跟着位移，看起来下方卡片离 banner 远了。
///   改成"按住图 → 放大"的纯本地交互：不影响 list layout，spring 仅在 banner 内部。
///
/// 行为：
///   - 仅响应按住图（非点击）：onTapDown 启动 spring.value=峰值，
///     onTapUp / onTapCancel 触发 SpringSimulation 回弹。
///   - 峰值放大 [_kPeakScale] (1.0 → 1.06x)。
///   - 松手用 [SpringSimulation] 回弹，~1-2 次可见震荡，~400 ms 落定。
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
  static const double _kPeakScale = 0.06; // 1.0 → 1.06x（克制）
  // 质量 1 + 刚度 380 + 阻尼比 0.55（欠阻尼）。
  // damping 必须是 sqrt(stiffness * mass) 的倍数 → 不能用 const（sqrt 不是常量）。
  static final SpringDescription _kSpring = SpringDescription(
    mass: 1.0,
    stiffness: 380.0,
    damping: 0.55 * 2.0 * math.sqrt(380.0), // ≈ 21.45
  );

  // ---------- 状态 ----------
  late final AnimationController _spring;

  @override
  void initState() {
    super.initState();
    // bounded 控制器：0..1，0=静止，1=峰值
    _spring = AnimationController(vsync: this);
  }

  void _onTapDown(TapDownDetails _) {
    _spring.stop();
    _spring.animateTo(1.0, duration: const Duration(milliseconds: 120));
  }

  void _onRelease() {
    if (_spring.value == 0) return;
    _spring.animateWith(
      SpringSimulation(_kSpring, _spring.value, 0.0, 0.0),
    );
  }

  void _onTapCancel() => _onRelease();

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: _onTapDown,
      onTapUp: (_) => _onRelease(),
      onTapCancel: _onTapCancel,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _spring,
        builder: (context, child) {
          return Transform.scale(
            scale: 1.0 + _spring.value * _kPeakScale,
            alignment: Alignment.center,
            child: child,
          );
        },
        child: SizedBox.expand(
          child: widget.imagePath != null
              ? Image.file(
                  File(widget.imagePath!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => widget.fallback,
                )
              : widget.fallback,
        ),
      ),
    );
  }
}
