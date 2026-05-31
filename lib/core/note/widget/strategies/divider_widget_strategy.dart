import 'package:flutter/material.dart';
import '../../core/core.dart';
import '../block_type_info.dart';
import '../block_widget_strategy.dart';

class DividerWidgetStrategy extends BlockWidgetStrategy {
  @override
  List<BlockTypeInfo> get typeInfoList => const [
    BlockTypeInfo(prototype: DividerType(), icon: Icons.horizontal_rule, label: '—', category: BlockTypeCategory.media),
  ];

  @override
  Widget build(BuildContext context, Block block, BlockCallbacks callbacks) {
    return const Divider(height: 1, thickness: 1);
  }
}
