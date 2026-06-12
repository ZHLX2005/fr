/// 全屏手势捕获层
///
/// 使用 [Positioned.fill] + [Listener] 覆盖整个棋盘区域，
/// [HitTestBehavior.translucent] 确保零延迟穿透手势事件。
///
/// 将四个触摸事件（按下/移动/抬起/取消）直接委托给
/// [GameController] 的对应处理方法，传递触摸坐标、格子尺寸
/// 和间距参数，由控制器层完成坐标到棋盘位置的映射和游戏逻辑判断。
///
/// 内部子组件为 [SizedBox.expand] 空组件，仅做事件捕获，不参与渲染。
import 'package:flutter/material.dart';
import '../game_ui_state.dart';

/// 全屏手势层 — Listener + HitTestBehavior.translucent 零延迟
class TouchView extends StatelessWidget {
  final GameController controller;
  final double cellSize;
  final double distance;

  const TouchView({
    super.key,
    required this.controller,
    required this.cellSize,
    required this.distance,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          controller.handleTouchBegan(
            event.localPosition, cellSize, distance,
          );
        },
        onPointerMove: (event) {
          controller.handleTouchMoved(
            event.localPosition, cellSize, distance,
          );
        },
        onPointerUp: (event) {
          controller.handleTouchEnded(
            event.localPosition, cellSize, distance,
          );
        },
        onPointerCancel: (event) {
          controller.handleTouchCancelled();
        },
        child: const SizedBox.expand(),
      ),
    );
  }
}
