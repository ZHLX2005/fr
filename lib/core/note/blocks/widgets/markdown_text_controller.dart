import 'package:flutter/material.dart';

/// 在 TextField 中渲染行内 Markdown 格式的 Controller
///
/// 存储纯文本，通过重写 buildTextSpan 将 `**bold**`、`*italic*`、`` `code` ``
/// 中的内容以对应样式渲染，同时保留定界符文本以确保光标位置准确。
class MarkdownTextController extends TextEditingController {
  MarkdownTextController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (text.isEmpty) return TextSpan(text: '', style: style);

    try {
      final spans = _parse(context, text, style ?? const TextStyle());
      if (spans.length == 1 && spans[0].style == null) {
        return TextSpan(text: text, style: style);
      }
      return TextSpan(style: style, children: spans);
    } catch (_) {
      return TextSpan(text: text, style: style);
    }
  }

  List<TextSpan> _parse(BuildContext context, String source, TextStyle base) {
    final spans = <TextSpan>[];
    int last = 0;
    final surface = Theme.of(context).colorScheme.surfaceContainerHighest;

    for (final m in _pattern.allMatches(source)) {
      // 未匹配部分
      if (m.start > last) {
        spans.add(TextSpan(text: source.substring(last, m.start)));
      }

      final full = m.group(0)!;
      String inner;
      TextStyle innerStyle;

      if (m.group(1) != null) {
        // **bold**
        inner = m.group(1)!;
        innerStyle = base.copyWith(fontWeight: FontWeight.bold);
      } else if (m.group(2) != null) {
        // *italic*
        inner = m.group(2)!;
        innerStyle = base.copyWith(fontStyle: FontStyle.italic);
      } else {
        // `code`
        inner = m.group(3)!;
        innerStyle = base.copyWith(
          fontFamily: 'monospace',
          backgroundColor: surface,
        );
      }

      // 分割符长度（两侧相等）
      final dl = (full.length - inner.length) ~/ 2;

      // 保留定界符文本以保证光标位置准确
      if (dl > 0) {
        spans.add(TextSpan(text: full.substring(0, dl)));
      }
      spans.add(TextSpan(text: inner, style: innerStyle));
      if (dl > 0) {
        spans.add(TextSpan(text: full.substring(full.length - dl)));
      }

      last = m.end;
    }

    if (last < source.length) {
      spans.add(TextSpan(text: source.substring(last)));
    }

    return spans;
  }

  static final RegExp _pattern = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*|`([^`]+)`');
}
