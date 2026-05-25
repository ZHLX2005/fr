import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/note/core/models/block.dart';
import '../../../core/note/core/type/type.dart';

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
Widget renderBlockContent(Block block, {VoidCallback? onToggleTodo, VoidCallback? onTapAddImage}) {
  final text = block.content.toPlainText();

  return switch (block.type) {
    PageType() => _pageContent(block),
    HeadingType() => _headingContent(block),
    TodoType() => _todoContent(block, onToggleTodo: onToggleTodo),
    DividerType() => const Divider(height: 1, thickness: 1),
    BulletListItemType() => _bulletContent(text),
    OrderedListItemType() => _orderedContent(block),
    QuoteType() => _quoteContent(text),
    CodeType() => _codeContent(block),
    CalloutType() => _calloutContent(block),
    ImageType() => _imageContent(block, onTapAddImage: onTapAddImage),
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

Widget _todoContent(Block block, {VoidCallback? onToggleTodo}) {
  final checked = (block.type as TodoType).checked;
  final text = block.content.toPlainText();
  return Row(
    children: [
      GestureDetector(
        onTap: onToggleTodo,
        child: Icon(
          checked ? Icons.check_box : Icons.check_box_outline_blank,
          size: 18,
          color: checked ? Colors.blue : Colors.grey,
        ),
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
  final number = (block.type as OrderedListItemType).number;
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
            child: Text(lang,
              style: TextStyle(fontSize: 11, color: Colors.grey[500], fontFamily: 'monospace')),
          ),
        Text(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
      ],
    ),
  );
}

Widget _imageContent(Block block, {VoidCallback? onTapAddImage}) {
  final imgType = block.type as ImageType;
  final src = imgType.src;
  final caption = imgType.caption;
  final width = imgType.width;
  final height = imgType.height;

  if (src.isEmpty) {
    return GestureDetector(
      onTap: onTapAddImage,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          children: [
            Icon(Icons.image_outlined, size: 32, color: Colors.grey[400]),
            const SizedBox(height: 4),
            Text('点击以添加图片', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          ],
        ),
      ),
    );
  }

  final isNetwork = src.startsWith('http://') || src.startsWith('https://');

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: isNetwork
            ? Image.network(
                src,
                width: width,
                height: height,
                fit: width != null || height != null ? BoxFit.cover : null,
                errorBuilder: (context, error, stackTrace) => _imageErrorPlaceholder(),
              )
            : Image.file(
                File(src),
                width: width,
                height: height,
                fit: width != null || height != null ? BoxFit.cover : null,
                errorBuilder: (context, error, stackTrace) => _imageErrorPlaceholder(),
              ),
      ),
      if (caption != null && caption.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(caption, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        ),
    ],
  );
}

Widget _imageErrorPlaceholder() {
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.grey[100],
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      children: [
        Icon(Icons.broken_image, color: Colors.grey[400]),
        const SizedBox(width: 8),
        Text('加载失败', style: TextStyle(color: Colors.grey[500])),
      ],
    ),
  );
}

Widget _calloutContent(Block block) {
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
        Text(icon, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
