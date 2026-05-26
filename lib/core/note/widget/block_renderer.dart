import 'package:flutter/material.dart';
import '../core/core.dart';
import 'widget.dart';

/// Block 渲染器 — 封装 block 的渲染和编辑样式逻辑。
class BlockRenderer {
  final BlockWidgetFactory _factory;

  BlockRenderer(this._factory);

  TextStyle? textStyleForType(Block block) {
    return switch (block.type) {
      HeadingType() => _headingStyle(block),
      CodeType() => const TextStyle(fontFamily: 'monospace', fontSize: 13),
      PageType() => const TextStyle(fontWeight: FontWeight.w600),
      QuoteType() => TextStyle(color: Colors.grey[700], fontStyle: FontStyle.italic),
      _ => null,
    };
  }

  TextStyle _headingStyle(Block block) {
    final level = (block.type as HeadingType).level;
    final sizes = [28.0, 22.0, 18.0, 16.0, 14.0, 13.0];
    return TextStyle(
      fontSize: sizes[level.clamp(1, 6) - 1],
      fontWeight: FontWeight.bold,
      height: 1.3,
    );
  }

  /// 所有策略提供的可创建类型列表。
  List<BlockTypeInfo> get typeInfoList => _factory.typeInfoList;

  Widget renderBlockContent(Block block, {VoidCallback? onToggleTodo, VoidCallback? onTapAddImage}) {
    return _factory.build(
      block,
      BlockCallbacks(onToggleTodo: onToggleTodo, onTapAddImage: onTapAddImage),
    );
  }
}
