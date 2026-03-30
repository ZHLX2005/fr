import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// Markdown 渲染器 Widget
/// 支持常用 Markdown 特性（轻量版）
class MarkdownRendererWidget extends StatelessWidget {
  final String data;
  final double? maxWidth;

  const MarkdownRendererWidget({
    super.key,
    required this.data,
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxWidth ?? MediaQuery.of(context).size.width * 0.85,
      ),
      child: MarkdownBody(
        data: data,
        selectable: false, // 禁用可选中以提升性能
        shrinkWrap: true,
        styleSheet: _staticStyleSheet(context),
        onTapLink: (text, href, title) {
          // 链接点击暂不处理
        },
      ),
    );
  }

  static MarkdownStyleSheet _staticStyleSheet(BuildContext context) {
    final theme = Theme.of(context);
    return MarkdownStyleSheet(
      p: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
      h1: theme.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold),
      h2: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
      h3: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
      code: TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        color: theme.colorScheme.primary,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
      ),
      codeblockDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 4),
        ),
      ),
    );
  }
}
