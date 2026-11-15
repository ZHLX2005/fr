import 'package:flutter/material.dart';

import '../../../../design_tokens/spacing.dart';
import '../../../../api/mnws/nxkv/nxkv_controller.dart';
import '../../../../api/mnws/nxkv/nxkv_md.dart';
import 'nxkv_widgets.dart';

/// 队列：当前主题 / 当前项目的任务清单（没有打开任何任务时的主区）。
///
/// 数据来自 controller 的 `tasks`（`localtask.tasks`，只回列表需要的字段）——
/// 抽屉与这里看的是**同一份**，抽屉里刚领的活这儿立刻就有。
/// 正文不在这里传：点开一条才 `localtask.get`。
///
/// 选中的是**组**时（[NxKvController.selectedBoardKey] 非空）画的是组队列：
/// 本组任务跨成员项目的队列，每条带归属项目 tag —— 组有组自己的活，
/// 不是「装着项目的文件夹」（面板 `#/group/<id>` 同款）。
///
/// 这一层不再自己拉数据、不再自己 push 详情：拉数据是 controller 的事，
/// 打开任务是外壳 [NxKvPage] 的事。视图只负责画。
class NxKvQueueView extends StatelessWidget {
  const NxKvQueueView({super.key, required this.controller, required this.onOpen});

  final NxKvController controller;

  /// 打开一条任务（外壳切主区）。带上物理落点队列 —— 组任务跨成员队列。
  final void Function(int id, String topicKey) onOpen;

  @override
  Widget build(BuildContext context) =>
      NxKvScope(controller: controller, builder: _body);

  Widget _body(BuildContext context) {
    final c = controller;
    if (c.loading && c.topics.isEmpty) {
      final cs = Theme.of(context).colorScheme;
      // 请求有 15s 超时窗口，这段别只给一圈转：说清在等谁，
      // 不然「转圈」和「卡死」在用户眼里是同一件事。
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '连 ${c.target.pcName} 上的 nx-kv…',
              style: TextStyle(fontSize: 11, color: cs.outline),
            ),
          ],
        ),
      );
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
    if (c.topics.isEmpty && c.boards.isEmpty) {
      return NxKvNotice(
        text: '这台机器上还没有任务主题',
        detail: '任务主题由工作目录派生：在某个目录里跑过一次 nx-kv 才会有。',
        actionLabel: '刷新',
        onAction: c.bootstrap,
      );
    }
    if (c.selectedBoardKey != null) return _groupBody(context, c);

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
            for (final t in c.tasks)
              _row(
                context,
                onTap: () => onOpen(t.id, c.selectedKey ?? ''),
                id: t.id,
                title: t.title,
                status: t.status,
                round: t.round,
                createdAt: t.createdAt,
              ),
        ],
      ),
    );
  }

  /// 组队列：本组任务（跨成员项目的队列，每条带归属项目 tag）。
  ///
  /// 数据一次拿全（`localtask.boardtasks`），切组不额外发请求；这里不做
  /// 「按项目分组」—— 组的语义是**一个队列**，按项目分组等于又把它拆回成员列表。
  Widget _groupBody(BuildContext context, NxKvController c) {
    final cs = Theme.of(context).colorScheme;
    final g = c.selectedGroup;
    final rows = c.groupTasks;
    return RefreshIndicator(
      onRefresh: c.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.md),
        children: [
          if (g != null && g.desc.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                g.desc,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, height: 1.45, color: cs.outline),
              ),
            ),
          _filters(c),
          if (!c.boardTasksKnown)
            NxKvNotice(
              text: '组任务数暂时拿不到',
              detail: '服务端这条读接口没回（老版本 nx-kv？）。刷新试试，项目队列不受影响。',
              actionLabel: '重试',
              onAction: c.loadBoardTasks,
            )
          else if (rows.isEmpty)
            NxKvNotice(
              text: c.statusFilter == null ? '这个组还没有任务' : '没有这个状态的任务',
              detail: c.statusFilter == null ? '点抽屉里的「新建」，落点选本组的一个绑定仓库。' : '换个筛选看看',
            )
          else
            for (final t in rows)
              _row(
                context,
                onTap: () => onOpen(t.id, t.topicKey),
                id: t.id,
                title: t.title,
                status: t.status,
                round: t.round,
                createdAt: t.createdAt,
                project: t.project,
              ),
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

  Widget _row(
    BuildContext context, {
    required VoidCallback onTap,
    required int id,
    required String title,
    required String status,
    required int round,
    required String createdAt,
    String? project,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
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
              child: Text('#$id', style: TextStyle(fontSize: 11, color: cs.outline)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.isEmpty ? '(无标题)' : title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      NxKvStatusTag(status),
                      const SizedBox(width: AppSpacing.xxs),
                      if (round > 1)
                        Text('第$round轮', style: TextStyle(fontSize: 10, color: cs.outline)),
                      if (project != null && project.isNotEmpty) ...[
                        const SizedBox(width: AppSpacing.xxs),
                        Flexible(
                          child: Text(
                            project,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 10, color: cs.primary.withValues(alpha: 0.8)),
                          ),
                        ),
                      ],
                      const SizedBox(width: AppSpacing.xxs),
                      Text(humanTime(createdAt), style: TextStyle(fontSize: 10, color: cs.outline)),
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
