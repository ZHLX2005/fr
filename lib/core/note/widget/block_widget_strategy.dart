import 'package:flutter/material.dart';
import '../core/models/block.dart';

/// 块 widget 所需的外部回调。
class BlockCallbacks {
  final VoidCallback? onToggleTodo;
  final VoidCallback? onTapAddImage;

  const BlockCallbacks({this.onToggleTodo, this.onTapAddImage});
}

/// 块 widget 策略接口。
///
/// 每个 BlockType 对应一个策略，负责该类型的 widget 构建。
abstract class BlockWidgetStrategy {
  Widget build(Block block, BlockCallbacks callbacks);
}
