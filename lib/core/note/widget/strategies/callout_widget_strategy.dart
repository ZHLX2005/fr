import 'package:flutter/material.dart';
import '../../core/core.dart';
import '../block_type_info.dart';
import '../block_widget_strategy.dart';

class CalloutWidgetStrategy extends BlockWidgetStrategy {
  @override
  List<BlockTypeInfo> get typeInfoList => const [
    BlockTypeInfo(prototype: CalloutType(), icon: Icons.info_outline, label: '💡', category: BlockTypeCategory.text),
  ];

  @override
  Widget buildEditor(Block block, BlockCallbacks callbacks, {required Widget textField}) {
    final icon = (block.type as CalloutType).icon;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Text(icon.isEmpty ? '💡' : icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(child: textField),
        ],
      ),
    );
  }

  @override
  Widget build(Block block, BlockCallbacks callbacks) {
    final icon = (block.type as CalloutType).icon;
    final text = block.content.toPlainText();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Text(icon.isEmpty ? '💡' : icon,
            style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
