// KV 清单 —— 通用 UI 组件（Tab chip / 快捷 topic chip / 任务卡片）。
// 视觉骨架走 styles-skill → border-emphasis-style：装饰统一主题色，
// 添加 = green / 主操作；完成 = blue；删除/清空 = red / 危险。

import 'package:flutter/material.dart';

import '../../../core/design/emphasis_button.dart';
import 'kvcli_todo_models.dart';

/// 待办 / 已完成 切换 chip
class KvTabChip extends StatelessWidget {
  const KvTabChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = selected ? scheme.primary : scheme.outline;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: selected ? 0.12 : 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: accent.withValues(alpha: selected ? 0.5 : 0.3),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: accent,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

/// 快捷 topic chip：点击回填主题框。删除集中在管理弹层，chip 不带 ✕。
class KvTopicChip extends StatelessWidget {
  const KvTopicChip({
    super.key,
    required this.label,
    this.onTap,
  });

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: accent.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: accent,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// 任务卡片：信息列 + 编辑/删除 + （待办）完成按钮。
class KvTaskCard extends StatelessWidget {
  const KvTaskCard({
    super.key,
    required this.task,
    required this.isOpen,
    this.onDone,
    this.onEdit,
    this.onDelete,
    this.onClone,
  });

  final KvTask task;
  final bool isOpen;
  final VoidCallback? onDone;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onClone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '#${task.id}',
                        style: TextStyle(
                          color: scheme.outline,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          task.topic,
                          style: TextStyle(
                            color: scheme.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    task.text,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isOpen ? '创建于 ${task.createdAt}' : '完成于 ${task.doneAt}',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 11,
                    ),
                  ),
                  if (!isOpen && task.note.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'note: ${task.note}',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _IconAction(
                      icon: Icons.content_copy_outlined,
                      tooltip: '克隆',
                      onTap: onClone,
                    ),
                    _IconAction(
                      icon: Icons.edit_outlined,
                      tooltip: '编辑',
                      onTap: onEdit,
                    ),
                    _IconAction(
                      icon: Icons.delete_outline,
                      tooltip: '删除',
                      color: scheme.error,
                      onTap: onDelete,
                    ),
                  ],
                ),
                if (onDone != null) ...[
                  const SizedBox(height: 2),
                  OutlinedButton.icon(
                    onPressed: onDone,
                    style: EmphasisButton.borderEmphasis(
                      context,
                      color: Colors.blue,
                    ),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('完成'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 紧凑图标按钮（编辑 / 删除）
class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon, size: 18, color: color),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }
}
