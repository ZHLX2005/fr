// 比价计算器 —— 主题选择/管理 sheet

import 'package:flutter/material.dart';

class PriceTopicPickerSheet extends StatelessWidget {
  const PriceTopicPickerSheet({
    super.key,
    required this.entries,
    required this.currentId,
    required this.onNew,
    required this.onDelete,
  });

  final List<MapEntry<String, Map>> entries;
  final String? currentId;
  final VoidCallback onNew;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.folder_open_rounded, color: scheme.primary),
                const SizedBox(width: 8),
                const Text('比价主题',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton.icon(
                  onPressed: onNew,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('新建'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
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
                  itemCount: entries.length,
                  separatorBuilder: (ctx, i) => const SizedBox(height: 6),
                  itemBuilder: (ctx, i) {
                    final e = entries[i];
                    final map = e.value;
                    final id = map['id'] as String;
                    final title = (map['title'] as String?)?.trim() ?? '';
                    final rows = (map['rows'] as List?) ?? const [];
                    final isCurrent = id == currentId;
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
                              : Colors.transparent,
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
                        subtitle: Text('${rows.length} 行'),
                        trailing: IconButton(
                          tooltip: '删除主题',
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.red.withValues(alpha: 0.8),
                          ),
                          onPressed: () =>
                              _confirmDelete(context, id, title),
                        ),
                        onTap: () => Navigator.pop(ctx, id),
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
        title: const Text('删除主题'),
        content: Text('确定删除「${title.isEmpty ? '未命名主题' : title}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) onDelete(id);
  }
}
