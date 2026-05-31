import 'package:flutter/material.dart';
import '../core/core.dart';
import 'widget.dart';

/// Block 渲染器 — 封装 block 的渲染和编辑样式逻辑。
class BlockRenderer {
  final BlockWidgetFactory _factory;

  BlockRenderer(this._factory);

  TextStyle? textStyleForType(Block block, BuildContext context) {
    final theme = Theme.of(context);
    return switch (block.type) {
      HeadingType() => _headingStyle(block, theme),
      CodeType() => TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: theme.colorScheme.primary,
        ),
      PageType() => TextStyle(fontWeight: FontWeight.w600),
      _ => null,
    };
  }

  TextStyle _headingStyle(Block block, ThemeData theme) {
    final level = (block.type as HeadingType).level;
    final style = switch (level) {
      1 => theme.textTheme.headlineLarge,
      2 => theme.textTheme.headlineMedium,
      _ => theme.textTheme.headlineSmall,
    };
    return style?.copyWith(fontWeight: FontWeight.bold, height: 1.3) ?? const TextStyle(fontSize: 18, fontWeight: FontWeight.bold);
  }

  /// 所有策略提供的可创建类型列表。
  List<BlockTypeInfo> get typeInfoList => _factory.typeInfoList;

  Widget renderBlockContent(BuildContext context, Block block, {VoidCallback? onToggleTodo, VoidCallback? onTapAddImage}) {
    return _factory.build(
      context,
      block,
      BlockCallbacks(onToggleTodo: onToggleTodo, onTapAddImage: onTapAddImage),
    );
  }

  Widget buildEditor(BuildContext context, Block block, {required Widget textField, VoidCallback? onToggleTodo}) {
    return _factory.buildEditor(
      context,
      block,
      BlockCallbacks(onToggleTodo: onToggleTodo),
      textField: textField,
    );
  }
}
