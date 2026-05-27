import 'package:flutter/material.dart';
import '../core/block.dart';
import 'block_type_info.dart';

/// 块 widget 所需的外部回调。
class BlockCallbacks {
  final VoidCallback? onToggleTodo;
  final VoidCallback? onTapAddImage;

  const BlockCallbacks({this.onToggleTodo, this.onTapAddImage});
}

/// 块 widget 策略接口。
///
/// 每个 BlockType 对应一个策略，负责该类型的 widget 构建和 UI 元信息。
abstract class BlockWidgetStrategy {
  Widget build(Block block, BlockCallbacks callbacks);

  /// 编辑态：将 [textField] 包裹上类型装饰后返回。
  /// 默认直接返回 textField，子类可覆写添加前缀/后缀/背景等。
  Widget buildEditor(Block block, BlockCallbacks callbacks, {required Widget textField}) {
    return textField;
  }

  /// 该策略提供的可创建类型列表。
  /// 大部分策略返回单元素列表，Heading 返回 3 个（H1/H2/H3），Page 返回空。
  List<BlockTypeInfo> get typeInfoList;
}
