import 'package:flutter/material.dart';
import 'package:nx_kv_client/nx_kv_client.dart' as kv;

import '../../../../design_tokens/spacing.dart';
import 'nxkv_controller.dart';
import 'nxkv_widgets.dart';

/// 「主题」视图：nx-kv 的队列容器本身（不是「看板」意义上的主题）。
///
/// 一个主题 = 一个完整工作目录（`D:\DevProjects\my\github\nx-kv`）。
/// 这页回答三个问题：**这活属于谁**（仓库/目录）、**现在什么状态**（现状 + 计数）、
/// **点进去看什么**（跳队列）。
class NxKvTopicsView extends StatelessWidget {
  const NxKvTopicsView({super.key, required this.controller, required this.onOpen});

  final NxKvController controller;

  /// 点一个主题 → 切到队列页并选中它。
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c.loading && c.topics.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (c.topics.isEmpty) {
      return NxKvNotice(
        text: '还没有任务主题',
        detail: c.error,
        actionLabel: '刷新',
        onAction: c.bootstrap,
        isError: c.error != null,
      );
    }
    return RefreshIndicator(
      onRefresh: c.refresh,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          for (final t in c.topics) _topicCard(context, t),
        ],
      ),
    );
  }

  Widget _topicCard(BuildContext context, kv.LocaltaskListTopic t) {
    final cs = Theme.of(context).colorScheme;
    final repo = t.repo;
    return InkWell(
      onTap: () => onOpen(t.key),
      child: NxKvSection(
        title: t.name,
        trailing: Text(
          '${t.pending} 待领 · ${t.claimed} 进行中',
          style: TextStyle(fontSize: 10, color: cs.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (t.summary.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(
                  t.summary,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.55),
                ),
              ),
            if (repo != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                child: Row(
                  children: [
                    Icon(Icons.folder_outlined, size: 12, color: cs.outline),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        repo.key,
                        style: TextStyle(fontSize: 10, color: cs.outline),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.cwd,
                    style: TextStyle(fontSize: 10, color: cs.outline.withValues(alpha: 0.9)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  '${t.total} 条',
                  style: TextStyle(fontSize: 10, color: cs.outline),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, size: 14, color: cs.outline),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
