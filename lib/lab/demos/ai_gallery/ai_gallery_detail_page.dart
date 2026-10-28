import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import 'ai_gallery_scanner.dart';

/// 缩略图加载（photo_manager 原生缩图 → Image.memory）。
///
/// gallery_manage_page 同款模式：项目未引入 photo_manager_image_provider，
/// 统一走 FutureBuilder + Image.memory。
class _AssetThumb extends StatelessWidget {
  final AssetEntity asset;
  final int size;

  const _AssetThumb({required this.asset, this.size = 900});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<Uint8List?>(
      future: asset.thumbnailDataWithSize(ThumbnailSize(size, size)),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return ColoredBox(color: scheme.surfaceContainerHigh);
        }
        final data = snap.data;
        if (data == null) {
          return ColoredBox(
            color: scheme.surfaceContainerHigh,
            child: Icon(Icons.broken_image_outlined,
                color: scheme.onSurfaceVariant),
          );
        }
        return Image.memory(data, fit: BoxFit.cover);
      },
    );
  }
}

/// AI 图库详情页 —— 内容完全由 AI 返回的结构化 JSON 驱动。
///
/// 布局：顶部大图 + title/description/group/tags/importance 标准区 +
/// 「其余全部字段」动态渲染区（AI 加了什么就显示什么——二维码内容、
/// 文档要点、地点、时间等，字段名原样做标题，值 toString）。
class AiGalleryDetailPage extends StatelessWidget {
  final AiScanItem item;

  const AiGalleryDetailPage({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final result = item.result;

    return Scaffold(
      appBar: AppBar(
        title: Text(result?.title ?? '详情'),
        actions: [
          if (result != null && result.isImportant)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: _ImportanceBadge(important: true),
              ),
            ),
        ],
      ),
      body: result == null
          ? const Center(child: Text('暂无分析结果'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                // 大图
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: _AssetThumb(asset: item.asset, size: 900),
                  ),
                ),
                const SizedBox(height: 16),

                // 标准区：title / description / group / tags
                Row(
                  children: [
                    _GroupPill(group: result.group),
                    if (result.isImportant) ...[
                      const SizedBox(width: 8),
                      const _ImportanceBadge(important: true),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  result.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                if (result.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    result.description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
                if (result.tags.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tag in result.tags) _TagChip(tag: tag),
                    ],
                  ),
                ],

                // 动态区：AI 返回的全部额外字段
                if (result.extraFields.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Text(
                    'AI 结构化数据',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final e in result.extraFields.entries)
                    _FieldCard(
                      name: e.key,
                      value: _prettyValue(e.value),
                    ),
                ],

                const SizedBox(height: 16),
                Text(
                  '扫描于 ${_formatTime(result.scannedAt)} · ${result.fields.length} 个字段',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }

  static String _prettyValue(Object? value) {
    if (value is List) {
      return value.map((e) => e.toString()).join('、');
    }
    if (value is Map) {
      return value.entries
          .map((e) => '${e.key}: ${e.value}')
          .join('\n');
    }
    return value?.toString() ?? '';
  }

  static String _formatTime(DateTime t) =>
      '${t.month}-${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// 分组胶囊。
class _GroupPill extends StatelessWidget {
  final String group;

  const _GroupPill({required this.group});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        group,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// 重要性徽标（AI 推断 importance == high 时显示）。
class _ImportanceBadge extends StatelessWidget {
  final bool important;

  const _ImportanceBadge({required this.important});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.priority_high_rounded,
            size: 11,
            color: scheme.onTertiaryContainer,
          ),
          const SizedBox(width: 3),
          Text(
            '重要',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onTertiaryContainer,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String tag;

  const _TagChip({required this.tag});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '#$tag',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

/// 单个动态字段卡片。
class _FieldCard extends StatelessWidget {
  final String name;
  final String value;

  const _FieldCard({required this.name, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
        ],
      ),
    );
  }
}
