import 'package:flutter/material.dart';
import '../core/block.dart';
import 'block_type_info.dart';
import 'block_widget_strategy.dart';

/// Block widget 工厂。
///
/// 与 MessageWidgetFactory 相同的 O(1) Map 策略查找模式。
class BlockWidgetFactory {
  final Map<String, BlockWidgetStrategy> _strategies;

  BlockWidgetFactory(this._strategies);

  /// 所有策略提供的可创建类型列表。
  List<BlockTypeInfo> get typeInfoList =>
      _strategies.values.expand((s) => s.typeInfoList).toList();

  /// 根据 block.type.tag 查找策略并构建 widget。
  Widget build(BuildContext context, Block block, [BlockCallbacks? callbacks]) {
    final strategy = _strategies[block.type.tag];
    if (strategy == null) {
      return Text(block.content.toPlainText());
    }
    return RepaintBoundary(
      child: strategy.build(context, block, callbacks ?? const BlockCallbacks()),
    );
  }

  /// 编辑态：将 [textField] 包裹上类型装饰。
  Widget buildEditor(BuildContext context, Block block, BlockCallbacks callbacks, {required Widget textField}) {
    final strategy = _strategies[block.type.tag];
    if (strategy == null) return textField;
    return strategy.buildEditor(context, block, callbacks, textField: textField);
  }
}
