import 'package:flutter/material.dart';

import '../../../../design_tokens/radius.dart';
import '../../../../design_tokens/spacing.dart';
import '../../../../api/mnws/nxkv/nxkv_controller.dart';
import '../../../../api/mnws/nxkv/nxkv_md.dart';
import 'nxkv_motion.dart';
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
          _filters(context, c),
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
          _filters(context, c),
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

  /// 状态筛选：胶囊分段（选中浮起、未选中贴着底）。
  ///
  /// 不用 `ChoiceChip`：Material 的 chip 自带描边 + 勾选位，四个并排像一排标签；
  /// iOS 的分段控件是**一块底 + 一个滑块**，这里用同样的语言（背景块跟随选中项
  /// 做透明度过渡），切换时只动颜色不动布局，眼睛不会被跳动的边框吸引。
  Widget _filters(BuildContext context, NxKvController c) {
    const items = <(String?, String)>[
      (null, '全部'),
      ('pending', '待领'),
      ('claimed', '进行中'),
      ('done', '已完成'),
    ];
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 36,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                children: [
                  for (final (value, label) in items)
                    Expanded(
                      child: NxKvPress(
                        onTap: () => c.filterTasks(value),
                        scale: 0.94,
                        semanticLabel: label,
                        child: AnimatedContainer(
                          duration: NxKvMotion.base,
                          curve: NxKvMotion.snap,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: c.statusFilter == value ? cs.surface : Colors.transparent,
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: c.statusFilter == value
                                ? [
                                    BoxShadow(
                                      color: cs.shadow.withValues(alpha: 0.10),
                                      blurRadius: 6,
                                      offset: const Offset(0, 1),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: c.statusFilter == value ? FontWeight.w600 : FontWeight.w400,
                              color: c.statusFilter == value ? cs.onSurface : cs.outline,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          AnimatedSize(
            duration: NxKvMotion.base,
            curve: NxKvMotion.glide,
            child: c.tasksLoading
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  /// 一条任务 = 一张卡：圆角 + 极轻底色，按下去整块弹一下。
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
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: NxKvPress(
        onTap: onTap,
        semanticLabel: '任务 $id，$title',
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
          decoration: BoxDecoration(
            color: cs.onSurfaceVariant.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 编号块：等宽数字，位数变了也不左右抖
              Container(
                width: 38,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  '#$id',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 10),
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
                    const SizedBox(height: 5),
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
              Icon(Icons.chevron_right_rounded, size: 18, color: cs.outline.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }
}
