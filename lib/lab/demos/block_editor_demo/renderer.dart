import 'package:flutter/material.dart';
import '../../../core/note/core/core.dart';
import '../../../core/note/widget/widget.dart';

/// 全局共享的工厂实例。
final BlockWidgetFactory _factory = BlockWidgetBuilder().build();

/// 根据 BlockType 返回编辑时使用的 TextStyle。
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

/// 根据 BlockType 返回类型专属的 Widget。
/// 委托给 [BlockWidgetFactory] 进行 O(1) 策略查找。
Widget renderBlockContent(Block block, {VoidCallback? onToggleTodo, VoidCallback? onTapAddImage}) {
  return _factory.build(
    block,
    BlockCallbacks(onToggleTodo: onToggleTodo, onTapAddImage: onTapAddImage),
  );
}
