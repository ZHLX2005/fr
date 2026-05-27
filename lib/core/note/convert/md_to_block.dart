import '../core/core.dart';

/// Markdown → `List<Block>` 转换。
///
/// 仅支持行级语法，内联格式（粗体/斜体/链接）存为纯文本。
class MdToBlock {
  int _counter = 0;

  MdToBlock();

  /// 解析 markdown 文本，返回 blocks。
  /// 空输入或解析失败返回空列表。
  List<Block> parse(String source) {
    if (source.trim().isEmpty) return [];

    final lines = source.split('\n');
    final blocks = <Block>[];
    var i = 0;

    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.isEmpty) { i++; continue; }

      if (trimmed.startsWith('```')) {
        final lang = trimmed.substring(3).trim();
        final codeLines = <String>[];
        i++;
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          codeLines.add(lines[i]);
          i++;
        }
        i++;
        blocks.add(Block(
          id: _nextId(),
          type: lang.isNotEmpty ? CodeType(language: lang) : const CodeType(),
          content: RichText.text(codeLines.join('\n')),
        ));
        continue;
      }

      final headingMatch = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(trimmed);
      if (headingMatch != null) {
        final level = headingMatch.group(1)!.length;
        final text = headingMatch.group(2)!.trim();
        blocks.add(Block(
          id: _nextId(),
          type: HeadingType(level: level),
          content: RichText.text(text),
        ));
        i++;
        continue;
      }

      if (RegExp(r'^-{3,}$').hasMatch(trimmed)) {
        blocks.add(Block(id: _nextId(), type: const DividerType()));
        i++;
        continue;
      }

      final todoMatch = RegExp(r'^-\s+\[(x| )\]\s+(.+)$', caseSensitive: false).firstMatch(trimmed);
      if (todoMatch != null) {
        final checked = todoMatch.group(1)!.toLowerCase() == 'x';
        blocks.add(Block(
          id: _nextId(),
          type: TodoType(checked: checked),
          content: RichText.text(todoMatch.group(2)!.trim()),
        ));
        i++;
        continue;
      }

      final bulletMatch = RegExp(r'^-\s+(.+)$').firstMatch(trimmed);
      if (bulletMatch != null) {
        blocks.add(Block(
          id: _nextId(),
          type: const BulletListItemType(),
          content: RichText.text(bulletMatch.group(1)!.trim()),
        ));
        i++;
        continue;
      }

      final orderMatch = RegExp(r'^(\d+)\.\s+(.+)$').firstMatch(trimmed);
      if (orderMatch != null) {
        final number = int.tryParse(orderMatch.group(1)!) ?? 1;
        blocks.add(Block(
          id: _nextId(),
          type: OrderedListItemType(number: number),
          content: RichText.text(orderMatch.group(2)!.trim()),
        ));
        i++;
        continue;
      }

      if (trimmed.startsWith('> ')) {
        blocks.add(Block(
          id: _nextId(),
          type: const QuoteType(),
          content: RichText.text(trimmed.substring(2).trim()),
        ));
        i++;
        continue;
      }

      blocks.add(Block(
        id: _nextId(),
        type: const ParagraphType(),
        content: RichText.text(trimmed),
      ));
      i++;
    }

    return blocks;
  }

  String _nextId() => 'md_import_${++_counter}';
}
