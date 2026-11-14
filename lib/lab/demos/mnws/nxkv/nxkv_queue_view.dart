import 'package:flutter/material.dart';
import 'package:nx_kv_client/nx_kv_client.dart' as kv;

import '../../../../design_tokens/spacing.dart';
import 'nxkv_controller.dart';
import 'nxkv_md.dart';
import 'nxkv_widgets.dart';

/// 队列：当前主题的任务清单（没有打开任何任务时的主区）。
///
/// 数据来自 controller 的 `tasks`（`localtask.tasks`，只回列表需要的字段）——
/// 抽屉与这里看的是**同一份**，抽屉里刚领的活这儿立刻就有。
/// 正文不在这里传：点开一条才 `localtask.get`。
///
/// 这一层不再自己拉数据、不再自己 push 详情：拉数据是 controller 的事，
/// 打开任务是外壳 [NxKvPage] 的事。视图只负责画。
class NxKvQueueView extends StatelessWidget {
  const NxKvQueueView({super.key, required this.controller, required this.onOpen});

  final NxKvController controller;

  /// 打开一条任务（外壳切主区）。
  final void Function(int id) onOpen;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c.loading && c.topics.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (c.error != null && c.topics.isEmpty) {
      return NxKvNotice(
        text: '连不上 nx-kv',
        detail: c.error,
        actionLabel: '重试',
        onAction: c.bootstrap,
        isError: true,
      );
    }
    if (c.topics.isEmpty) {
      return NxKvNotice(
        text: '这台机器上还没有任务主题',
        detail: '任务主题由工作目录派生：在某个目录里跑过一次 nx-kv 才会有。',
        actionLabel: '刷新',
        onAction: c.bootstrap,
      );
    }

    return RefreshIndicator(
      onRefresh: c.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.md),
        children: [
          _filters(c),
          if (c.tasksError != null)
            NxKvNotice(
              text: '这个主题的清单拉不到',
              detail: c.tasksError,
              actionLabel: '重试',
              onAction: c.loadTasks,
              isError: true,
            )
          else if (c.tasksLoading && c.tasks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (c.tasks.isEmpty)
            NxKvNotice(
              text: c.statusFilter == null ? '这个主题还没有任务' : '没有这个状态的任务',
              detail: c.statusFilter == null ? '点左上角菜单 →「新建」派一条，或等 agent 交活。' : '换个筛选看看',
            )
          else
            for (final t in c.tasks) _row(context, t),
        ],
      ),
    );
  }

  /// 状态筛选：四个 chip 一行。抽屉里也有一个紧凑版菜单，两边写的是同一份状态。
  Widget _filters(NxKvController c) {
    const items = <(String?, String)>[
      (null, '全部'),
      ('pending', '待领'),
      ('claimed', '进行中'),
      ('done', '已完成'),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Row(
        children: [
          for (final (value, label) in items)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xxs),
              child: ChoiceChip(
                label: Text(label, style: const TextStyle(fontSize: 11)),
                selected: c.statusFilter == value,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onSelected: (_) => c.filterTasks(value),
              ),
            ),
          const Spacer(),
          if (c.tasksLoading)
            const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, kv.LocaltaskTasksTask t) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => onOpen(t.id),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs, horizontal: AppSpacing.xxs),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 34,
              child: Text('#${t.id}', style: TextStyle(fontSize: 11, color: cs.outline)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.title.isEmpty ? '(无标题)' : t.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      NxKvStatusTag(t.status),
                      const SizedBox(width: AppSpacing.xxs),
                      if (t.round > 1)
                        Text('第${t.round}轮', style: TextStyle(fontSize: 10, color: cs.outline)),
                      const SizedBox(width: AppSpacing.xxs),
                      Text(humanTime(t.createdAt), style: TextStyle(fontSize: 10, color: cs.outline)),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: cs.outline),
          ],
        ),
      ),
    );
  }
}
