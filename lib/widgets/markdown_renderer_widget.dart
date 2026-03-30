import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

/// Markdown 渲染器 Widget
/// 支持代码高亮、链接点击、图片显示等常用 Markdown 特性
class MarkdownRendererWidget extends StatelessWidget {
  /// Markdown 内容
  final String data;

  /// 是否可选中文字
  final bool selectable;

  /// 最大宽度
  final double? maxWidth;

  /// 内边距
  final EdgeInsets? padding;

  /// 样式配置
  final MarkdownRendererStyle? style;

  /// 链接点击回调
  final void Function(String href)? onLinkTap;

  /// 图片点击回调
  final void Function(String src, String? title)? onImageTap;

  const MarkdownRendererWidget({
    super.key,
    required this.data,
    this.selectable = true,
    this.maxWidth,
    this.padding,
    this.style,
    this.onLinkTap,
    this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultStyle = style ?? MarkdownRendererStyle.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxWidth ?? MediaQuery.of(context).size.width * 0.85,
      ),
      child: Markdown(
        data: data,
        selectable: selectable,
        padding: padding ?? EdgeInsets.zero,
        styleSheet: _buildStyleSheet(context, theme, defaultStyle),
        onTapLink: (text, href, title) {
          if (href != null) {
            onLinkTap?.call(href);
          }
        },
        builders: {
          'code': _CodeBlockBuilder(theme: theme),
          'pre': _PreBlockBuilder(theme: theme),
        },
        imageBuilder: (Uri uri, String? title, String? alt) {
          return _MarkdownImage(
            src: uri.toString(),
            title: title,
            alt: alt,
            onTap: () => onImageTap?.call(uri.toString(), title),
          );
        },
      ),
    );
  }

  MarkdownStyleSheet _buildStyleSheet(
    BuildContext context,
    ThemeData theme,
    MarkdownRendererStyle style,
  ) {
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;

    return MarkdownStyleSheet(
      // 标题样式
      h1: textTheme.headlineLarge?.copyWith(
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
      ),
      h2: textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
      ),
      h3: textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
      ),
      h4: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
      ),
      h5: textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
      ),
      h6: textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
      ),
      // 段落样式
      p: textTheme.bodyMedium?.copyWith(
        color: colorScheme.onSurface,
        height: 1.5,
      ),
      // 代码块样式
      code: TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        color: colorScheme.primary,
        backgroundColor: colorScheme.surfaceContainerHighest,
      ),
      codeblockPadding: const EdgeInsets.all(12),
      codeblockDecoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      // 引用样式
      blockquote: textTheme.bodyMedium?.copyWith(
        color: colorScheme.onSurfaceVariant,
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: colorScheme.primary,
            width: 4,
          ),
        ),
      ),
      blockquotePadding: const EdgeInsets.only(left: 16),
      // 列表样式
      listBullet: textTheme.bodyMedium?.copyWith(
        color: colorScheme.primary,
      ),
      // 链接样式
      a: TextStyle(
        color: colorScheme.primary,
        decoration: TextDecoration.underline,
      ),
      // 水平线样式
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant,
            width: 1,
          ),
        ),
      ),
      // 表格样式
      tableHead: textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.bold,
      ),
      tableBody: textTheme.bodyMedium,
      tableBorder: TableBorder.all(
        color: colorScheme.outlineVariant,
        width: 1,
      ),
      tableColumnWidth: const FlexColumnWidth(),
      tableCellsPadding: const EdgeInsets.all(8),
    );
  }
}

/// Markdown 渲染器样式配置
class MarkdownRendererStyle {
  final TextStyle? h1Style;
  final TextStyle? h2Style;
  final TextStyle? h3Style;
  final TextStyle? pStyle;
  final TextStyle? codeStyle;
  final Color? blockquoteColor;

  const MarkdownRendererStyle({
    this.h1Style,
    this.h2Style,
    this.h3Style,
    this.pStyle,
    this.codeStyle,
    this.blockquoteColor,
  });

  static MarkdownRendererStyle of(BuildContext context) {
    return const MarkdownRendererStyle();
  }
}

/// 代码块 Builder
class _CodeBlockBuilder extends MarkdownElementBuilder {
  final ThemeData theme;

  _CodeBlockBuilder({required this.theme});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final code = element.textContent;
    final language = element.attributes['class']?.replaceFirst('language-', '');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (language != null && language.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                language,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              code,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pre 标签 Builder
class _PreBlockBuilder extends MarkdownElementBuilder {
  final ThemeData theme;

  _PreBlockBuilder({required this.theme});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    // 让 code builder 处理
    return null;
  }
}

/// Markdown 图片组件
class _MarkdownImage extends StatelessWidget {
  final String src;
  final String? title;
  final String? alt;
  final VoidCallback? onTap;

  const _MarkdownImage({
    required this.src,
    this.title,
    this.alt,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            src,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                width: double.infinity,
                height: 200,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Center(
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                        : null,
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: double.infinity,
                height: 100,
                color: Theme.of(context).colorScheme.errorContainer,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.broken_image,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      if (alt != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            alt!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
