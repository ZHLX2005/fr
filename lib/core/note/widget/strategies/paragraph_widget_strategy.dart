import 'package:flutter/material.dart';
import '../../core/core.dart';
import '../block_type_info.dart';
import '../block_widget_strategy.dart';

class ParagraphWidgetStrategy extends BlockWidgetStrategy {
  @override
  List<BlockTypeInfo> get typeInfoList => const [
    BlockTypeInfo(prototype: ParagraphType(), icon: Icons.text_fields, label: 'P', category: BlockTypeCategory.text),
  ];

  @override
  Widget build(Block block, BlockCallbacks callbacks) {
    return Text(block.content.toPlainText());
  }
}
