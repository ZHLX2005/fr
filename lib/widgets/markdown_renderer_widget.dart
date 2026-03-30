import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// Markdown 渲染器 Widget
/// 支持常用 Markdown 特性
class MarkdownRendererWidget extends StatelessWidget {
  /// Markdown 内容
  final String data;

  /// 是否可选中文字
  final bool selectable;

  /// 最大宽度
  final double? maxWidth;

  /// 内边距
  final EdgeInsets? padding;

  /// 链接点击回调
  final void Function(String href)? onLinkTap;

  const MarkdownRendererWidget({
    super.key,
    required this.data,
    this.selectable = true,
    this.maxWidth,
    this.padding,
    this.onLinkTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxWidth ?? MediaQuery.of(context).size.width * 0.85,
      ),
      child: Padding(
        padding: padding ?? EdgeInsets.zero,
        child: MarkdownBody(
          data: data,
          selectable: selectable,
          styleSheet: _buildStyleSheet(context, theme),
          onTapLink: (text, href, title) {
            if (href != null) {
              onLinkTap?.call(href);
            }
          },
        ),
      ),
    );
  }

  MarkdownStyleSheet _buildStyleSheet(BuildContext context, ThemeData theme) {
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;

    return MarkdownStyleSheet(
      h1: textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold),
      h2: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
      h3: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
      h4: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      h5: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      h6: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
      p: textTheme.bodyMedium?.copyWith(height: 1.5),
      code: TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        color: colorScheme.primary,
        backgroundColor: colorScheme.surfaceContainerHighest,
      ),
      codeblockDecoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: colorScheme.primary, width: 4),
        ),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant, width: 1),
        ),
      ),
    );
  }
}
