import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// 自包含下拉弹性 Banner —— 监听**手指**在 banner 内的 PointerMoveEvent 驱动
/// spring，**不**读 list 的 `position.pixels`，因此 list 整体不会跟着位移。
///
/// 设计原因：之前用 `BouncingScrollPhysics` + `SliverAppBar` / `NestedScrollView`
/// 都会让 `position.pixels` 短暂为负，导致下方菜单 sliver 跟着下移产生空白。
/// 改用"局部手指监听"：banner 自己在 200px 盒子内做 spring 拉伸，下方菜单
/// 永远紧贴 banner 不动。
///
/// 行为：
///   - 在 banner 内的 `onPointerDown` 启动拖动，`onPointerMove` 累加 dy
///   - 用抗阻曲线把 dy 映射成 spring.value，clamp 到 [_kMaxStretch] = 120 px
///   - 图层永远比 banner 高 2×_kMaxStretch（静止时被外层 clip）
///   - 下拉时 translate(v) 把上方多出的 120px 段露出来 + scale 1.15x
///   - `onPointerUp` / `onPointerCancel` 触发 [SpringSimulation] 回弹
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

  /// 单击 banner 时触发的回调（沿用原有的"裁剪/移除"底部菜单）。
  final VoidCallback onTap;

  @override
  State<SpringyBanner> createState() => _SpringyBannerState();
}

class _SpringyBannerState extends State<SpringyBanner>
    with SingleTickerProviderStateMixin {
  // ---------- 常量 ----------
  static const double _kMaxStretch = 120.0; // 抗阻饱和点（px）
  static const double _kPeakScale = 0.15; // 1.0 → 1.15x

  // 质量 1 + 刚度 320 + 阻尼比 0.55（欠阻尼），保证 1-2 次可见回弹。
  // damping 必须是 sqrt(stiffness * mass) 的倍数 → 不能用 const（sqrt 不是常量）。
  static final SpringDescription _kSpring = SpringDescription(
    mass: 1.0,
    stiffness: 320.0,
    damping: 0.55 * 2.0 * math.sqrt(320.0), // ≈ 19.75
  );

  // ---------- 状态 ----------
  late final AnimationController _spring;
  double _dragStartY = 0.0; // 手指按下时 banner 内的局部 Y

  @override
  void initState() {
    super.initState();
    _spring = AnimationController.unbounded(vsync: this);
  }

  void _onPointerDown(PointerDownEvent e) {
    _spring.stop();
    _dragStartY = e.localPosition.dy;
  }

  void _onPointerMove(PointerMoveEvent e) {
    final dy = e.localPosition.dy - _dragStartY;
    if (dy <= 0) {
      // 上滑不响应（避免在 banner 内向上滑时干扰）
      return;
    }
    final raw = dy.clamp(0.0, _kMaxStretch);
    // iOS 橡皮筋抗阻：overscroll / (1 + overscroll / max)
    final overscroll = raw / (1.0 + raw / _kMaxStretch);
    _spring.value = overscroll;
  }

  void _onPointerEnd() {
    if (_spring.value == 0) return;
    _spring.animateWith(
      SpringSimulation(_kSpring, _spring.value, 0.0, 0.0),
    );
  }

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      // 监听原始指针事件，手指离开才触发 onPointerUp（避免 GestureDetector 的判定）
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: (_) => _onPointerEnd(),
      onPointerCancel: (_) => _onPointerEnd(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          // 几何：
          //   banner 自身高 h，静止时被外层 FlexibleSpaceBar 的 ClipRect 裁切。
          //   图层高度 = h + 2*overshoot（上下各 overshoot=120 像素），
          //   起始 top = -overshoot（顶部 -120 露出 banner 顶部之上，被外层 clip），
          //   静止时图覆盖 0..h（无空白）。
          //   下拉 v 像素 → 把图 translate 向上 v → 顶部 -120 → -120-v，
          //   底部 h+120 → h+120-v，新的"图的上方延展"进入视野，
          //   **永远填满整个 0..h，无任何空白**。
          final overshoot = _kMaxStretch;
          final bgHeight = h + 2 * overshoot;
          return SizedBox(
            width: w,
            height: h,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 1. 图层：永远比 banner 高 2×overshoot，顶部 -overshoot 起始
                Positioned(
                  left: 0,
                  right: 0,
                  top: -overshoot,
                  height: bgHeight,
                  child: AnimatedBuilder(
                    animation: _spring,
                    builder: (context, _) {
                      final v = _spring.value;
                      // 关键：v > 0 时把图向上 translate v，**不要**向下！
                      return Transform.translate(
                        offset: Offset(0, -v),
                        child: Transform.scale(
                          scale: 1.0 + (v / _kMaxStretch) * _kPeakScale,
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            width: w,
                            height: bgHeight,
                            child: widget.imagePath != null
                                ? Image.file(
                                    File(widget.imagePath!),
                                    fit: BoxFit.cover,
                                    width: w,
                                    height: bgHeight,
                                    alignment: Alignment.topCenter,
                                    errorBuilder: (_, _, _) =>
                                        widget.fallback,
                                  )
                                : widget.fallback,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // 2. 透明点击层：始终 banner 原尺寸，**不**跟随 spring 变形
                Positioned.fill(
                  child: GestureDetector(
                    onTap: widget.onTap,
                    behavior: HitTestBehavior.opaque,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
