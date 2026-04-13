// Schema 链接解析器
//
// 解析文本中的 Markdown 风格链接: [文字](schema://path)
// 支持嵌套和转义

import 'schema_service.dart';

/// 解析后的文本片段
class SchemaTextSpan {
  final String text;
  final bool isLink;
  final String? schemaPath;

  const SchemaTextSpan.plain(this.text)
      : isLink = false,
        schemaPath = null;

  const SchemaTextSpan.link(this.text, this.schemaPath)
      : isLink = true;

  bool get isPlain => !isLink;
}

/// 解析结果
class SchemaParseResult {
  final List<SchemaTextSpan> spans;
  final List<String> errors;

  const SchemaParseResult({
    required this.spans,
    this.errors = const [],
  });

  bool get hasErrors => errors.isNotEmpty;
  bool get hasLinks => spans.any((s) => s.isLink);
}

/// Schema 链接解析器
class SchemaLinkParser {
  SchemaLinkParser._();

  /// 正则: 匹配 [文字](schema://path) 格式
  static final _linkPattern = RegExp(
    r'\[([^\]]*)\]\(([^\)]+)\)',
    multiLine: true,
  );

  /// 转义字符
  static final _escapePattern = RegExp(r'\\(.)');

  /// 解析文本中的 schema 链接
  static SchemaParseResult parse(String text) {
    final spans = <SchemaTextSpan>[];
    final errors = <String>[];

    int lastEnd = 0;

    for (final match in _linkPattern.allMatches(text)) {
      // 添加匹配前的纯文本
      if (match.start > lastEnd) {
        final plainText = _unescape(text.substring(lastEnd, match.start));
        if (plainText.isNotEmpty) {
          spans.add(SchemaTextSpan.plain(plainText));
        }
      }

      final linkText = match.group(1)!;
      final schemaPath = match.group(2)!;

      // 验证 schema 格式
      if (schemaPath.startsWith('fr://')) {
        spans.add(SchemaTextSpan.link(linkText, schemaPath));
      } else {
        // 不是 fr:// schema，当作普通文本处理
        errors.add('不支持的 schema: $schemaPath');
        spans.add(SchemaTextSpan.plain(match.group(0)!));
      }

      lastEnd = match.end;
    }

    // 添加剩余文本
    if (lastEnd < text.length) {
      final remainingText = _unescape(text.substring(lastEnd));
      if (remainingText.isNotEmpty) {
        spans.add(SchemaTextSpan.plain(remainingText));
      }
    }

    return SchemaParseResult(spans: spans, errors: errors);
  }

  /// 转义处理
  static String _unescape(String text) {
    return text.replaceAllMapped(_escapePattern, (m) {
      final ch = m.group(1)!;
      // 常见的转义
      switch (ch) {
        case 'n':
          return '\n';
        case 't':
          return '\t';
        case '[':
          return '[';
        case ']':
          return ']';
        case '(':
          return '(';
        case ')':
          return ')';
        default:
          return ch;
      }
    });
  }

  /// 检查文本是否包含 schema 链接
  static bool containsLinks(String text) {
    return _linkPattern.hasMatch(text);
  }

  /// 提取所有 schema 链接
  static List<String> extractSchemaPaths(String text) {
    return _linkPattern
        .allMatches(text)
        .map((m) => m.group(2)!)
        .where((p) => p.startsWith('fr://'))
        .toList();
  }

  /// 从纯文本生成可跳转版本
  /// 将 demo 标题自动转换为链接
  static String autoLink(String text) {
    final result = StringBuffer();
    final entries = schemaRegistry.getAll();

    // 按标题长度降序排列，避免短标题先匹配
    entries.sort((a, b) => b.title.length.compareTo(a.title.length));

    int lastEnd = 0;
    final allMatches = <_MatchInfo>[];

    for (final entry in entries) {
      final pattern = RegExp(RegExp.escape(entry.title));
      for (final match in pattern.allMatches(text)) {
        allMatches.add(_MatchInfo(match.start, match.end, entry.title, entry.schema));
      }
    }

    // 按起始位置排序
    allMatches.sort((a, b) => a.start.compareTo(b.start));

    final usedRanges = <_Range>[];
    for (final match in allMatches) {
      bool overlaps = false;
      for (final range in usedRanges) {
        if (match.start < range.end && match.end > range.start) {
          overlaps = true;
          break;
        }
      }
      if (!overlaps) {
        usedRanges.add(_Range(match.start, match.end));
        result.write(text.substring(lastEnd, match.start));
        result.write('[${match.displayText}](${match.schema})');
        lastEnd = match.end;
      }
    }

    result.write(text.substring(lastEnd));
    return result.toString();
  }
}

class _MatchInfo {
  final int start;
  final int end;
  final String displayText;
  final String schema;

  _MatchInfo(this.start, this.end, this.displayText, this.schema);
}

class _Range {
  final int start;
  final int end;

  _Range(this.start, this.end);
}
