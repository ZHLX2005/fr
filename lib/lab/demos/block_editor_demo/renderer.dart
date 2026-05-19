import 'package:flutter/material.dart';
import '../../../core/note/core/block.dart';
import '../../../core/note/core/block_type.dart';

/// 根据 BlockType 返回类型专属的 Widget。
Widget renderBlockContent(Block block) {
  final text = block.content.toPlainText();

  return switch (block.type) {
    BlockType.page => _pageContent(block),
    BlockType.heading => _headingContent(block),
    BlockType.todo => _todoContent(block),
    BlockType.divider => const Divider(height: 1, thickness: 1),
    BlockType.bulletListItem => _bulletContent(text),
    BlockType.orderedListItem => _orderedContent(block),
    BlockType.quote => _quoteContent(text),
    BlockType.code => _codeContent(block),
    BlockType.callout => _calloutContent(block),
    _ => Text(text),
  };
}

Widget _pageContent(Block block) {
  return Text(
    block.content.toPlainText(),
    style: const TextStyle(fontWeight: FontWeight.w600),
  );
}

Widget _headingContent(Block block) {
  final level = block.data.get<int>('level') ?? 1;
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

Widget _todoContent(Block block) {
  final checked = block.data.get<bool>('checked') ?? false;
  final text = block.content.toPlainText();
  return Row(
    children: [
      Icon(
        checked ? Icons.check_box : Icons.check_box_outline_blank,
        size: 18,
        color: checked ? Colors.blue : Colors.grey,
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          text,
          style: TextStyle(
            decoration: checked ? TextDecoration.lineThrough : null,
            color: checked ? Colors.grey : null,
          ),
        ),
      ),
    ],
  );
}

Widget _bulletContent(String text) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('• ', style: TextStyle(fontSize: 16)),
      Expanded(child: Text(text)),
    ],
  );
}

Widget _orderedContent(Block block) {
  final number = block.data.get<int>('number') ?? 1;
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$number. ', style: const TextStyle(fontWeight: FontWeight.w500)),
      Expanded(child: Text(block.content.toPlainText())),
    ],
  );
}

Widget _quoteContent(String text) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(width: 3, margin: const EdgeInsets.only(right: 8), color: Colors.grey[400]),
      Expanded(
        child: Text(text,
          style: TextStyle(color: Colors.grey[700], fontStyle: FontStyle.italic)),
      ),
    ],
  );
}

Widget _codeContent(Block block) {
  final lang = block.data.get<String>('language') ?? '';
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
            child: Text(lang,
              style: TextStyle(fontSize: 11, color: Colors.grey[500], fontFamily: 'monospace')),
          ),
        Text(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
      ],
    ),
  );
}

Widget _calloutContent(Block block) {
  final icon = block.data.get<String>('icon') ?? '💡';
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
        Text(icon, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
