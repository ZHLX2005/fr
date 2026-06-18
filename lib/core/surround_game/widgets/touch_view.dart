/// 全屏手势捕获层
///
/// 使用 [Positioned.fill] + [Listener] 覆盖整个棋盘区域，
/// [HitTestBehavior.translucent] 确保零延迟穿透手势事件。
///
/// 将四个触摸事件（按下/移动/抬起/取消）通过回调回调给父组件，
/// 自身不依赖 [GameController] 或任何游戏状态模型。
///
/// 内部子组件为 [SizedBox.expand] 空组件，仅做事件捕获，不参与渲染。
import 'package:flutter/material.dart';

/// 触摸事件回调签名
typedef TouchEventHandler = void Function(
  Offset localPosition,
  double cellSize,
  double distance,
);

/// 触摸取消回调签名（无需坐标）
typedef TouchCancelHandler = void Function();

/// 全屏手势层 — Listener + HitTestBehavior.translucent 零延迟
///
/// 纯事件转发：四个回调对应四个触控生命周期，不引入游戏状态依赖。
class TouchView extends StatelessWidget {
  final double cellSize;
  final double distance;
  final TouchEventHandler onPointerDown;
  final TouchEventHandler onPointerMove;
  final TouchEventHandler onPointerUp;
  final TouchCancelHandler onPointerCancel;

  const TouchView({
    super.key,
    required this.cellSize,
    required this.distance,
    required this.onPointerDown,
    required this.onPointerMove,
    required this.onPointerUp,
    required this.onPointerCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          onPointerDown(event.localPosition, cellSize, distance);
        },
        onPointerMove: (event) {
          onPointerMove(event.localPosition, cellSize, distance);
        },
        onPointerUp: (event) {
          onPointerUp(event.localPosition, cellSize, distance);
        },
        onPointerCancel: (event) {
          onPointerCancel();
        },
        child: const SizedBox.expand(),
      ),
    );
  }
}
