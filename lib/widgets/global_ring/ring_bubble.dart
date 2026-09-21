// 全局圆环本体 —— 拖动 + 松手吸附到左/右边缘 + 点击回调。
//
// 性能取向（这是常驻在所有页面之上的一层，必须做到"静止时零成本"）：
//   1. 位置状态 (_pos) 只活在本 State 里，拖动时 setState 只重建圆环这一棵子树，
//      宿主 Stack 和它下面的整页都不会 rebuild。
//   2. 静止时不跑任何 ticker —— _snapCtrl 只在吸附的 300ms 内 forward，
//      跑完自然停；没有无限循环动画。
//   3. 外面包 RepaintBoundary，吸附/拖动只重绘圆环这一层 layer。
//   4. 不用 BackdropFilter（毛玻璃）—— 那会让每帧都对整屏做 blur，
//      是这一层唯一可能真正拖慢帧率的东西。
//
// 命中测试：圆环只在自己 56x56 的盒子里拦截触摸（HitTestBehavior.opaque），
// 盒子之外的事件照常穿透到下面的页面。

import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/material.dart';

import '../context_colors.dart';
import 'const_global_ring.dart';
import 'ring_position_store.dart';

class RingBubble extends StatefulWidget {
  const RingBubble({super.key, required this.onTap});

  /// 点击圆环（非拖动）时触发。
  final VoidCallback onTap;

  @override
  State<RingBubble> createState() => _RingBubbleState();
}

class _RingBubbleState extends State<RingBubble>
    with SingleTickerProviderStateMixin {
  static const _store = RingPositionStore();

  late final AnimationController _snapCtrl = AnimationController(
    vsync: this,
    duration: ConstGlobalRing.snapDuration,
  )..addListener(_onSnapTick);
  Animation<Offset>? _snapAnim;

  /// 圆环左上角在屏幕坐标系中的像素位置。
  Offset _pos = Offset.zero;

  Size _screen = Size.zero;

  /// 底部避让带 = 底部栏 + 安全区 + 边距（见 ConstGlobalRing.bottomBarHeight）
  double _bottomReserve = ConstGlobalRing.margin;

  bool _initialized = false;

  /// 用户已手动拖过 → 不再用持久化的旧位置覆盖当前落点。
  bool _userMoved = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _screen = MediaQuery.sizeOf(context);
    _bottomReserve = ConstGlobalRing.bottomBarHeight +
        ConstGlobalRing.margin +
        MediaQuery.viewPaddingOf(context).bottom;

    if (!_initialized) {
      _initialized = true;
      _pos = _clamp(_defaultPos());
      unawaited(_restore());
    } else {
      // 转屏 / 分屏导致尺寸变化：重新 clamp，别把圆环留在屏幕外
      _pos = _clamp(_pos);
    }
  }

  @override
  void dispose() {
    _snapCtrl
      ..removeListener(_onSnapTick)
      ..dispose();
    super.dispose();
  }

  /// 默认落位：右侧、纵向约 72%（拇指够得着，又不压底部栏）。
  Offset _defaultPos() => Offset(
        _screen.width * ConstGlobalRing.defaultNormX,
        _screen.height * ConstGlobalRing.defaultNormY,
      );

  Future<void> _restore() async {
    final saved = await _store.load(_screen);
    if (!mounted || saved == null || _userMoved) return;
    setState(() => _pos = _clamp(saved));
  }

  /// 夹在"左/上 margin ~ 右/下 减 自身尺寸减 margin"之间。
  /// 屏幕比圆环还小的极端情况（分屏小窗）用 max() 兜底，避免 clamp 区间反转抛错。
  Offset _clamp(Offset p) => Offset(
        p.dx.clamp(
          ConstGlobalRing.margin,
          max(_screen.width - ConstGlobalRing.size - ConstGlobalRing.margin,
              ConstGlobalRing.margin),
        ),
        p.dy.clamp(
          ConstGlobalRing.margin,
          max(_screen.height - ConstGlobalRing.size - _bottomReserve,
              ConstGlobalRing.margin),
        ),
      );

  void _onSnapTick() {
    final anim = _snapAnim;
    if (anim == null) return;
    setState(() => _pos = anim.value);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    _userMoved = true;
    setState(() => _pos = _clamp(_pos + details.delta));
  }

  /// 松手吸附：比圆心与屏幕中线，吸到较近的那一侧；纵向保持不动。
  void _snapToEdge() {
    final toLeft = _pos.dx + ConstGlobalRing.size / 2 < _screen.width / 2;
    final target = _clamp(
      Offset(
        toLeft
            ? ConstGlobalRing.margin
            : _screen.width - ConstGlobalRing.size - ConstGlobalRing.margin,
        _pos.dy,
      ),
    );
    _snapAnim = Tween<Offset>(begin: _pos, end: target).animate(
      CurvedAnimation(parent: _snapCtrl, curve: const RingSnapCurve()),
    );
    _snapCtrl
      ..reset()
      ..forward();
    unawaited(_store.save(target, _screen));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Positioned(
      left: _pos.dx,
      top: _pos.dy,
      width: ConstGlobalRing.size,
      height: ConstGlobalRing.size,
      child: RepaintBoundary(
        child: Semantics(
          button: true,
          label: '提交 KV 需求',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            // 一旦进入拖动就掐掉可能正在跑的吸附动画，避免动画和手指抢 _pos
            onPanStart: (_) => _snapCtrl.stop(),
            onPanUpdate: _onPanUpdate,
            onPanEnd: (_) => _snapToEdge(),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.surface,
                border: Border.all(
                  color: colors.accent,
                  width: ConstGlobalRing.borderWidth,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF000000).withValues(alpha: 0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  Icons.add,
                  size: ConstGlobalRing.iconSize,
                  color: colors.accent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
