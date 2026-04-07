import 'package:flutter/material.dart';

/// DraggableWordCard 的控制器
/// 用于将手势事件转发给 WordDragNotifier
class DraggableWordCardController {
  /// 屏幕尺寸
  Size screenSize = Size.zero;

  /// 拖动开始回调
  VoidCallback? onDragStart;

  /// 拖动更新回调 (delta)
  void Function(Offset delta)? onDragUpdate;

  /// 拖动结束回调
  VoidCallback? onDragEnd;

  /// 处理拖动开始
  void handleDragStart(DragStartDetails details) {
    onDragStart?.call();
  }

  /// 处理拖动更新
  void handleDragUpdate(DragUpdateDetails details) {
    onDragUpdate?.call(details.delta);
  }

  /// 处理拖动结束
  void handleDragEnd(DragEndDetails details) {
    onDragEnd?.call();
  }
}
