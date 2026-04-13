// Schema 文本组件
//
// 支持在普通文本中嵌入可点击的 schema 链接
// 使用方式:
// ```dart
// SchemaText('这是一个 [悬浮截屏](fr://lab/demo/悬浮截屏) 示例')
// ```

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'schema_parser.dart';
import 'schema_navigator.dart';

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
        final effectiveLinkStyle = linkStyle ??
            defaultStyle?.copyWith(
              color: linkColor ?? theme.colorScheme.primary,
              decoration: TextDecoration.underline,
              decorationColor: linkColor ?? theme.colorScheme.primary,
            );

        return TextSpan(
          text: span.text,
          style: effectiveLinkStyle,
          recognizer: TapGestureRecognizer()
            ..onTap = () => _handleLinkTap(span.schemaPath!, span.text),
        );
      } else {
        return TextSpan(
          text: span.text,
          style: defaultStyle,
        );
      }
    }).toList();

    return RichText(
      text: TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }

  void _handleLinkTap(String schema, String displayText) {
    final shouldNavigate = onLinkTap?.call(schema, displayText);
    if (shouldNavigate != false) {
      SchemaNavigator.navigateToSchema(schema);
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
