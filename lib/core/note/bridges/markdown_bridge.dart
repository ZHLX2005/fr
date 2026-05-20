import '../blocks/blocks.dart';

/// BlockTree ↔ Markdown 转换器
///
/// 将块树导出为标准 Markdown，并从 Markdown 文本重建块树。
class MarkdownBridge {
  MarkdownBridge._();

  /// 将块树导出为 Markdown 字符串
  static String exportToMarkdown(BlockTree tree) {
    final buf = StringBuffer();
    _exportChildren(tree, BlockTree.rootId, 0, buf);
    return buf.toString();
  }

  /// 导出块树为纯文本
  static String exportToPlainText(BlockTree tree) {
    final builder = ContextBuilder(tree);
    return builder.buildFullText();
  }

  static void _exportChildren(BlockTree tree, String parentId, int depth, StringBuffer buf) {
    for (final childId in tree.childIdsOf(parentId)) {
      final block = tree.get(childId);
      if (block == null) continue;

      final text = block.content.toPlainText();
      final indent = '  ' * depth;

      switch (block.type) {
        case BlockType.heading:
          final level = block.data.get<int>('level') ?? 1;
          final prefix = '#' * level.clamp(1, 6);
          buf.writeln('$indent$prefix $text');
          buf.writeln();

        case BlockType.bulletListItem:
          buf.writeln('$indent- $text');

        case BlockType.orderedListItem:
          final number = block.data.get<int>('number');
          buf.writeln('$indent${number ?? 1}. $text');

        case BlockType.todo:
          final checked = block.data.get<bool>('checked') ?? false;
          buf.writeln('$indent- [${checked ? 'x' : ' '}] $text');

        case BlockType.quote:
          // 每行加 >
          for (final line in text.split('\n')) {
            buf.writeln('$indent> $line');
          }

        case BlockType.code:
          final lang = block.data.get<String>('language') ?? '';
          buf.writeln('$indent```$lang');
          buf.writeln(text);
          buf.writeln('$indent```');
          buf.writeln();

        case BlockType.divider:
          buf.writeln('$indent---');
          buf.writeln();

        case BlockType.callout:
          final icon = block.data.get<String>('icon') ?? '💡';
          buf.writeln('$indent> [!${icon == '⚠️' ? 'WARNING' : icon == '❌' ? 'DANGER' : 'NOTE'}]');
          buf.writeln('$indent> $text');
          buf.writeln();

        case BlockType.image:
          final src = block.data.get<String>('src') ?? '';
          final caption = block.data.get<String>('caption') ?? '';
          if (caption.isNotEmpty) {
            buf.writeln('$indent![$caption]($src)');
          } else {
            buf.writeln('$indent![]($src)');
          }

        case BlockType.bookmark:
          final url = block.data.get<String>('url') ?? text;
          buf.writeln('$indent[$text]($url)');

        case BlockType.embedCard:
          final title = block.data.get<String>('title') ?? text;
          buf.writeln('$indent[嵌入卡片: $title]');

        case BlockType.equation:
          final latex = block.data.get<String>('latex') ?? text;
          buf.writeln(r'$indent$$');
          buf.writeln(latex);
          buf.writeln(r'$$');

        default:
          // paragraph, toggle, page, database, columnList, column, syncedBlock
          if (text.isNotEmpty) {
            buf.writeln('$indent$text');
            buf.writeln();
          }
      }

      // 递归处理子块（toggle, column_list, 等容器类型）
      _exportChildren(tree, childId, depth + 1, buf);
    }
  }

  /// 将 Markdown 文本解析为块列表（返回根级块列表）
  ///
  /// 注意：部分高级格式（表格、嵌套列表等）暂不支持。
  /// 调用者需自行将块插入 BlockTree。
  static List<Block> parseMarkdown(String markdown) {
    final lines = markdown.split('\n');
    final blocks = <Block>[];
    int i = 0;

    while (i < lines.length) {
      final line = lines[i];

      // 跳过空行
      if (line.trim().isEmpty) {
        i++;
        continue;
      }

      Block? block;

      // 代码块 ``` lang
      if (line.trimLeft().startsWith('```')) {
        block = _parseCodeBlock(lines, i);
        if (block != null) {
          blocks.add(block);
          i += _codeBlockEnd(lines, i);
          continue;
        }
      }

      // 分割线 ---
      if (line.trimLeft().startsWith('---')) {
        blocks.add(Block(
          id: BlockId.generate(),
          type: BlockType.divider,
        ));
        i++;
        continue;
      }

      // Heading ##
      final headingMatch = RegExp(r'^(\s*)(#{1,6})\s+(.*)').firstMatch(line);
      if (headingMatch != null) {
        final level = headingMatch.group(2)!.length;
        final content = headingMatch.group(3) ?? '';
        blocks.add(Block(
          id: BlockId.generate(),
          type: BlockType.heading,
          content: RichText.text(content),
          data: BlockData.fromMap({'level': level}),
        ));
        i++;
        continue;
      }

      // Todo - [ ] / - [x]
      final todoMatch = RegExp(r'^(\s*)-\s\[([ xX])\]\s+(.*)').firstMatch(line.trimRight());
      if (todoMatch != null) {
        final checked = todoMatch.group(2)!.toLowerCase() == 'x';
        final content = todoMatch.group(3) ?? '';
        blocks.add(Block(
          id: BlockId.generate(),
          type: BlockType.todo,
          content: RichText.text(content),
          data: BlockData.fromMap({'checked': checked}),
        ));
        i++;
        continue;
      }

      // 无序列表 -
      final ulMatch = RegExp(r'^(\s*)-\s+(.*)').firstMatch(line);
      if (ulMatch != null) {
        final content = ulMatch.group(2) ?? '';
        blocks.add(Block(
          id: BlockId.generate(),
          type: BlockType.bulletListItem,
          content: RichText.text(content),
        ));
        i++;
        continue;
      }

      // 有序列表 1.
      final olMatch = RegExp(r'^(\s*)(\d+)\.\s+(.*)').firstMatch(line);
      if (olMatch != null) {
        final number = int.tryParse(olMatch.group(2) ?? '') ?? 1;
        final content = olMatch.group(3) ?? '';
        blocks.add(Block(
          id: BlockId.generate(),
          type: BlockType.orderedListItem,
          content: RichText.text(content),
          data: BlockData.fromMap({'number': number}),
        ));
        i++;
        continue;
      }

      // 引用 >
      if (line.trimLeft().startsWith('>')) {
        final quoteLines = <String>[];
        while (i < lines.length && lines[i].trimLeft().startsWith('>')) {
          final ql = lines[i].trimLeft();
          // 去除 > 前缀
          quoteLines.add(ql.replaceFirst(RegExp(r'^>\s?'), ''));
          i++;
        }
        final content = quoteLines.join('\n');
        blocks.add(Block(
          id: BlockId.generate(),
          type: BlockType.quote,
          content: RichText.text(content),
        ));
        continue;
      }

      // 默认：段落
      final paraLines = <String>[];
      while (i < lines.length && lines[i].trim().isNotEmpty && !lines[i].trimLeft().startsWith('#')) {
        paraLines.add(lines[i]);
        i++;
      }
      final content = paraLines.join('\n').trim();
      if (content.isNotEmpty) {
        blocks.add(Block(
          id: BlockId.generate(),
          type: BlockType.paragraph,
          content: RichText.text(content),
        ));
      }
    }

    return blocks;
  }

  static Block? _parseCodeBlock(List<String> lines, int start) {
    final firstLine = lines[start].trimLeft();
    final lang = firstLine.substring(3).trim();
    final codeLines = <String>[];
    int i = start + 1;
    while (i < lines.length && !lines[i].trimLeft().startsWith('```')) {
      codeLines.add(lines[i]);
      i++;
    }
    final code = codeLines.join('\n');
    if (code.isEmpty) return null;
    return Block(
      id: BlockId.generate(),
      type: BlockType.code,
      content: RichText.text(code),
      data: lang.isNotEmpty ? BlockData.fromMap({'language': lang}) : BlockData.empty(),
    );
  }

  static int _codeBlockEnd(List<String> lines, int start) {
    int i = start + 1;
    while (i < lines.length && !lines[i].trimLeft().startsWith('```')) {
      i++;
    }
    return i - start + 1;
  }
}
