import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

/// HTML 渲染器 Widget
/// 基于 flutter_widget_from_html 实现，支持大部分 HTML 标签
class HtmlRendererWidget extends StatelessWidget {
  /// HTML 内容
  final String data;

  /// 是否可选中文字
  final bool selectable;

  /// 最大宽度
  final double? maxWidth;

  /// 内边距
  final EdgeInsets? padding;

  /// 链接点击回调
  final void Function(String href)? onLinkTap;

  /// 图片点击回调
  final void Function(String src)? onImageTap;

  /// 自定义样式
  final HtmlRendererStyle? style;

  const HtmlRendererWidget({
    super.key,
    required this.data,
    this.selectable = true,
    this.maxWidth,
    this.padding,
    this.onLinkTap,
    this.onImageTap,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultStyle = style ?? HtmlRendererStyle.of(context);

    return Container(
      constraints: BoxConstraints(
        maxWidth: maxWidth ?? MediaQuery.of(context).size.width * 0.85,
      ),
      padding: padding ?? EdgeInsets.zero,
      child: HtmlWidget(
        data,
        selectable: selectable,
        onTapUrl: (url) {
          onLinkTap?.call(url);
          return true;
        },
        onImageTap: (src) {
          onImageTap?.call(src);
        },
        customStylesBuilder: (element) {
          return defaultStyle.toCssStyles();
        },
      ),
    );
  }
}

/// HTML 渲染器样式配置
class HtmlRendererStyle {
  final TextStyle? h1Style;
  final TextStyle? h2Style;
  final TextStyle? h3Style;
  final TextStyle? pStyle;
  final TextStyle? codeStyle;
  final Color? linkColor;
  final Color? blockquoteColor;

  const HtmlRendererStyle({
    this.h1Style,
    this.h2Style,
    this.h3Style,
    this.pStyle,
    this.codeStyle,
    this.linkColor,
    this.blockquoteColor,
  });

  static HtmlRendererStyle of(BuildContext context) {
    final theme = Theme.of(context);
    return HtmlRendererStyle(
      linkColor: theme.colorScheme.primary,
      blockquoteColor: theme.colorScheme.onSurfaceVariant,
    );
  }

  /// 转换为 flutter_widget_from_html 需要的 CSS 样式格式
  Map<String, String> toCssStyles() {
    final styles = <String, String>{};

    if (linkColor != null) {
      final hex = '#${linkColor!.value.toRadixString(16).padLeft(8, '0').substring(2)}';
      styles['a'] = 'color: $hex;';
    }
    if (blockquoteColor != null) {
      final hex = '#${blockquoteColor!.value.toRadixString(16).padLeft(8, '0').substring(2)}';
      styles['blockquote'] = 'border-left: 4px solid $hex; padding-left: 16px; font-style: italic;';
    }
    if (pStyle != null) {
      styles['p'] = 'margin: 8px 0;';
    }

    return styles;
  }
}
