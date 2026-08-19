// 比价计算器 —— 主题选择/管理 sheet
// 入参改为 PriceTopicSummary 列表，使 sheet 不依赖 Hive / PriceTopic。

import 'package:flutter/material.dart';
import '../../../widgets/context_colors.dart';

import 'price_compare_models.dart';

class PriceTopicPickerSheet extends StatelessWidget {
  PriceTopicPickerSheet({
    super.key,
    required this.summaries,
    required this.currentId,
    required this.onNew,
    required this.onDelete,
  });

  final List<PriceTopicSummary> summaries;
  final String? currentId;
  final VoidCallback onNew;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors.scheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.folder_open_rounded, color: scheme.primary),
                SizedBox(width: 8),
                const Text('比价主题',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600)),
                Spacer(),
                TextButton.icon(
                  onPressed: onNew,
                  icon: Icon(Icons.add_rounded),
                  label: const Text('新建'),
                ),
              ],
            ),
            SizedBox(height: 4),
            if (summaries.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  '还没有主题，点右上"新建"开始',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.outline),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: summaries.length,
                  separatorBuilder: (ctx, i) => SizedBox(height: 6),
                  itemBuilder: (ctx, i) {
                    final s = summaries[i];
                    final title = s.title.trim();
                    final subtitleText = s.createdAt == null
                        ? '${s.rowCount} 行'
                        : '${s.rowCount} 行 · 创建于 ${formatCreatedAt(s.createdAt!)}';
                    final isCurrent = s.id == currentId;
                    return Container(
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? scheme.primary.withValues(alpha: 0.08)
                            : scheme.surfaceContainerHighest
                                .withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isCurrent
                              ? scheme.primary.withValues(alpha: 0.45)
                              : Theme.of(context).colorScheme.surface.withValues(alpha: 0.0),
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        title: Text(
                          title.isEmpty ? '（未命名主题）' : title,
                          style: TextStyle(
                            fontWeight: isCurrent
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isCurrent
                                ? scheme.primary
                                : scheme.onSurface,
                          ),
                        ),
                        subtitle: Text(subtitleText),
                        trailing: IconButton(
                          tooltip: '删除主题',
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            color: Theme.of(context).colorScheme.error.withValues(alpha: 0.8),
                          ),
                          onPressed: () => _confirmDelete(context, s.id, title),
                        ),
                        onTap: () => Navigator.pop(ctx, s.id),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, String id, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除主题'),
        content: Text('确定删除「${title.isEmpty ? '未命名主题' : title}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) onDelete(id);
  }
}