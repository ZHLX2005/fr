import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

/// 嵌入类型常量
class EmbedTypes {
  EmbedTypes._();

  /// 卡片嵌入
  static const String card = 'embed_card';

  /// Markdown 块嵌入（后续阶段使用）
  static const String markdownBlock = 'markdown_block';
}

/// 嵌入卡片数据
class EmbedCardData {
  final String title;
  final String subtitle;
  final String? icon;
  final Map<String, dynamic>? extra;

  const EmbedCardData({
    required this.title,
    required this.subtitle,
    this.icon,
    this.extra,
  });

  factory EmbedCardData.fromJson(Map<String, dynamic> json) {
    return EmbedCardData(
      title: json['title']?.toString() ?? '未命名',
      subtitle: json['subtitle']?.toString() ?? '',
      icon: json['icon']?.toString(),
      extra: json['extra'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'subtitle': subtitle,
      if (icon != null) 'icon': icon,
      if (extra != null) 'extra': extra,
    };
  }

  String toPayload() => jsonEncode(toJson());

  factory EmbedCardData.fromPayload(String payload) {
    return EmbedCardData.fromJson(
      jsonDecode(payload) as Map<String, dynamic>,
    );
  }
}

/// 嵌入卡片构建器
///
/// 实现 flutter_quill 的 EmbedBuilder 接口
/// 用于渲染自定义嵌入卡片
class EmbedCardBuilder extends quill.EmbedBuilder {
  @override
  String get key => EmbedTypes.card;

  @override
  String toPlainText(quill.Embed node) {
    try {
      final data = EmbedCardData.fromPayload(node.value.data);
      return '[${data.title}]';
    } catch (_) {
      return '[嵌入卡片]';
    }
  }

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final node = embedContext.node;
    final EmbedCardData data;
    try {
      data = EmbedCardData.fromPayload(node.value.data);
    } catch (_) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Card(
        elevation: 1,
        child: InkWell(
          onTap: () => _onTap(context, data),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _parseIcon(data.icon),
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      if (data.subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          data.subtitle,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.open_in_new, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onTap(BuildContext context, EmbedCardData data) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('点击了: ${data.title}'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  IconData _parseIcon(String? iconName) {
    if (iconName == null) return Icons.article_outlined;
    switch (iconName) {
      case 'page':
        return Icons.insert_drive_file_outlined;
      case 'image':
        return Icons.image_outlined;
      case 'video':
        return Icons.videocam_outlined;
      case 'code':
        return Icons.code;
      case 'link':
        return Icons.link;
      default:
        return Icons.article_outlined;
    }
  }
}

/// Markdown 块嵌入构建器（后续阶段使用）
class MarkdownBlockBuilder extends quill.EmbedBuilder {
  @override
  String get key => EmbedTypes.markdownBlock;

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final node = embedContext.node;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.code,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Markdown 块',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              node.value.data,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }
}
