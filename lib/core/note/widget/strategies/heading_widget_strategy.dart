import 'package:flutter/material.dart';
import '../../core/core.dart';
import '../block_type_info.dart';
import '../block_widget_strategy.dart';

class HeadingWidgetStrategy extends BlockWidgetStrategy {
  @override
  List<BlockTypeInfo> get typeInfoList => const [
    BlockTypeInfo(prototype: HeadingType(level: 1), icon: Icons.looks_one, label: 'H1', category: BlockTypeCategory.heading),
    BlockTypeInfo(prototype: HeadingType(level: 2), icon: Icons.looks_two, label: 'H2', category: BlockTypeCategory.heading),
    BlockTypeInfo(prototype: HeadingType(level: 3), icon: Icons.looks_3, label: 'H3', category: BlockTypeCategory.heading),
  ];

  @override
  Widget build(Block block, BlockCallbacks callbacks) {
    final level = (block.type as HeadingType).level;
    final text = block.content.toPlainText();
    final sizes = [28.0, 22.0, 18.0, 16.0, 14.0, 13.0];
    return Text(
      text,
      style: TextStyle(
        fontSize: sizes[level.clamp(1, 6) - 1],
        fontWeight: FontWeight.bold,
        height: 1.3,
      ),
    );
  }
}
