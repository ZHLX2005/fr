import '../core/models/block.dart';
import '../core/models/block_data.dart';
import '../core/models/block_type.dart';
import '../core/text/rich_text.dart';

/// Markdown → List<Block> 转换。
///
/// 仅支持行级语法，内联格式（粗体/斜体/链接）存为纯文本。
class MdToBlock {
  /// 解析 markdown 文本，返回 blocks。
  /// 空输入或解析失败返回空列表。
  static List<Block> parse(String source) {
    if (source.trim().isEmpty) return [];

    final lines = source.split('\n');
    final blocks = <Block>[];
    var i = 0;

    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();

      // 跳过空行
      if (trimmed.isEmpty) {
        i++;
        continue;
      }

      // 代码块 ```lang
      if (trimmed.startsWith('```')) {
        final lang = trimmed.substring(3).trim();
        final codeLines = <String>[];
        i++;
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          codeLines.add(lines[i]);
          i++;
        }
        i++; // 跳过结束 ``` 或文件尾
        blocks.add(Block(
          id: _nextId(),
          type: BlockType.code,
          content: RichText.text(codeLines.join('\n')),
          data: lang.isNotEmpty
              ? BlockData.fromMap({'language': lang})
              : BlockData.empty(),
        ));
        continue;
      }

      // heading # ~ ######
      final headingMatch = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(trimmed);
      if (headingMatch != null) {
        final level = headingMatch.group(1)!.length;
        final text = headingMatch.group(2)!.trim();
        blocks.add(Block(
          id: _nextId(),
          type: BlockType.heading,
          content: RichText.text(text),
          data: BlockData.fromMap({'level': level}),
        ));
        i++;
        continue;
      }

      // divider ---
      if (RegExp(r'^-{3,}$').hasMatch(trimmed)) {
        blocks.add(Block(
          id: _nextId(),
          type: BlockType.divider,
        ));
        i++;
        continue;
      }

      // todo - [x] / - [ ]
      final todoMatch = RegExp(r'^-\s+\[(x| )\]\s+(.+)$', caseSensitive: false).firstMatch(trimmed);
      if (todoMatch != null) {
        final checked = todoMatch.group(1)!.toLowerCase() == 'x';
        final text = todoMatch.group(2)!.trim();
        blocks.add(Block(
          id: _nextId(),
          type: BlockType.todo,
          content: RichText.text(text),
          data: BlockData.fromMap({'checked': checked}),
        ));
        i++;
        continue;
      }

      // bulletListItem - item
      final bulletMatch = RegExp(r'^-\s+(.+)$').firstMatch(trimmed);
      if (bulletMatch != null) {
        blocks.add(Block(
          id: _nextId(),
          type: BlockType.bulletListItem,
          content: RichText.text(bulletMatch.group(1)!.trim()),
        ));
        i++;
        continue;
      }

      // orderedListItem 1. item
      final orderMatch = RegExp(r'^(\d+)\.\s+(.+)$').firstMatch(trimmed);
      if (orderMatch != null) {
        final number = int.tryParse(orderMatch.group(1)!) ?? 1;
        blocks.add(Block(
          id: _nextId(),
          type: BlockType.orderedListItem,
          content: RichText.text(orderMatch.group(2)!.trim()),
          data: BlockData.fromMap({'number': number}),
        ));
        i++;
        continue;
      }

      // quote > text
      if (trimmed.startsWith('> ')) {
        blocks.add(Block(
          id: _nextId(),
          type: BlockType.quote,
          content: RichText.text(trimmed.substring(2).trim()),
        ));
        i++;
        continue;
      }

      // 默认 → paragraph
      blocks.add(Block(
        id: _nextId(),
        type: BlockType.paragraph,
        content: RichText.text(trimmed),
      ));
      i++;
    }

    return blocks;
  }

  static int _counter = 0;
  static String _nextId() => 'md_import_${++_counter}';
}
