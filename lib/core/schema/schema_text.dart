// Schema 文本组件
//
// 支持在普通文本中嵌入可点击的 schema 链接
// 使用方式:
// ```dart
// SchemaText('这是一个 [悬浮截屏](fr://lab/demo/悬浮截屏) 示例')
// ```

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'fr_navigator.dart';

/// 解析后的文本片段
class SchemaTextSpan {
  final String text;
  final bool isLink;
  final String? schemaPath;

  const SchemaTextSpan.plain(this.text) : isLink = false, schemaPath = null;

  const SchemaTextSpan.link(this.text, this.schemaPath) : isLink = true;

  bool get isPlain => !isLink;
}

/// 解析结果
class SchemaParseResult {
  final List<SchemaTextSpan> spans;
  final List<String> errors;

  const SchemaParseResult({required this.spans, this.errors = const []});

  bool get hasErrors => errors.isNotEmpty;
  bool get hasLinks => spans.any((s) => s.isLink);
}

/// Schema 链接解析器（内部使用）
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
}

/// Schema 文本组件
class SchemaText extends StatelessWidget {
  /// 要显示的文本，支持 [文字](fr://lab/demo/key) 格式
  final String text;

  /// 默认文本样式
  final TextStyle? style;

  /// 链接文本样式
  final TextStyle? linkStyle;

  /// 链接颜色（如果使用 linkStyle 则忽略）
  final Color? linkColor;

  /// 点击回调（返回 false 阻止默认跳转）
  final bool Function(String schema, String displayText)? onLinkTap;

  /// 最大行数
  final int? maxLines;

  /// 文本溢出处理
  final TextOverflow? overflow;

  const SchemaText(
    this.text, {
    super.key,
    this.style,
    this.linkStyle,
    this.linkColor,
    this.onLinkTap,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultStyle = style ?? theme.textTheme.bodyMedium;

    final parsed = SchemaLinkParser.parse(text);

    if (!parsed.hasLinks) {
      // 没有链接，直接显示普通文本
      return Text(
        text,
        style: defaultStyle,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    // 构建 TextSpan 列表
    final spans = parsed.spans.map((span) {
      if (span.isLink) {
        final effectiveLinkStyle =
            linkStyle ??
            defaultStyle?.copyWith(
              color: linkColor ?? theme.colorScheme.primary,
              decoration: TextDecoration.underline,
              decorationColor: linkColor ?? theme.colorScheme.primary,
            );

        return TextSpan(
          text: span.text,
          style: effectiveLinkStyle,
          recognizer: TapGestureRecognizer()
            ..onTap = () => _handleLinkTap(context, span.schemaPath!, span.text),
        );
      } else {
        return TextSpan(text: span.text, style: defaultStyle);
      }
    }).toList();

    return RichText(
      text: TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }

  void _handleLinkTap(BuildContext context, String schema, String displayText) {
    final shouldNavigate = onLinkTap?.call(schema, displayText);
    if (shouldNavigate != false) {
      FrNavigator.handle(context, schema);
    }
  }
}

/// Schema 文本控制器（用于动态更新）
class SchemaTextController extends ChangeNotifier {
  String _text = '';

  String get text => _text;
  List<SchemaTextSpan> get spans => SchemaLinkParser.parse(_text).spans;
  bool get hasLinks => spans.any((s) => s.isLink);

  void setText(String value) {
    _text = value;
    notifyListeners();
  }

  void append(String value) {
    _text += value;
    notifyListeners();
  }

  void clear() {
    _text = '';
    notifyListeners();
  }
}

/// Schema 文本字段 - 带输入功能
class SchemaTextField extends StatefulWidget {
  /// 控制器
  final SchemaTextController? controller;

  /// 提示文本
  final String? hintText;

  /// 最大行数
  final int? maxLines;

  /// 提交回调
  final void Function(String value)? onSubmitted;

  const SchemaTextField({
    super.key,
    this.controller,
    this.hintText,
    this.maxLines,
    this.onSubmitted,
  });

  @override
  State<SchemaTextField> createState() => _SchemaTextFieldState();
}

class _SchemaTextFieldState extends State<SchemaTextField> {
  late TextEditingController _textController;
  late SchemaTextController _schemaController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _schemaController = widget.controller ?? SchemaTextController();

    _textController.addListener(_onTextChanged);
    _schemaController.addListener(_onSchemaChanged);
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _schemaController.removeListener(_onSchemaChanged);
    _textController.dispose();
    if (widget.controller == null) {
      _schemaController.dispose();
    }
    super.dispose();
  }

  void _onTextChanged() {
    if (_textController.text != _schemaController.text) {
      _schemaController.setText(_textController.text);
    }
  }

  void _onSchemaChanged() {
    if (_textController.text != _schemaController.text) {
      _textController.text = _schemaController.text;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 实时预览
        if (_schemaController.hasLinks)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SchemaText(
                _schemaController.text,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        // 输入框
        TextField(
          controller: _textController,
          maxLines: widget.maxLines,
          decoration: InputDecoration(
            hintText: widget.hintText ?? '输入文本，支持 [文字](fr://lab/demo/key) 格式',
            border: const OutlineInputBorder(),
          ),
          onSubmitted: widget.onSubmitted,
        ),
      ],
    );
  }
}