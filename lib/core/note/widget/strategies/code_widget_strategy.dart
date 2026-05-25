import 'package:flutter/material.dart';
import '../../core/type/type.dart';
import '../../core/models/block.dart';
import '../block_widget_strategy.dart';

class CodeWidgetStrategy extends BlockWidgetStrategy {
  @override
  Widget build(Block block, BlockCallbacks callbacks) {
    final lang = (block.type as CodeType).language;
    final text = block.content.toPlainText();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lang.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                lang,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[500],
                  fontFamily: 'monospace',
                ),
              ),
            ),
          Text(
            text,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ],
      ),
    );
  }
}
