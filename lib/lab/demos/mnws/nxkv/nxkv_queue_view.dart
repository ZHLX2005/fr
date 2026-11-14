import 'package:flutter/material.dart';
import 'package:nx_kv_client/nx_kv_client.dart' as kv;

import '../../../../core/note/composer/md_composer.dart';
import '../../../../design_tokens/spacing.dart';
import 'nxkv_controller.dart';
import 'nxkv_detail_page.dart';
import 'nxkv_md.dart';
import 'nxkv_widgets.dart';

/// 「队列」视图：一个主题里的任务清单 + 领一条 + 新建。
///
/// 数据来自 `localtask.tasks`（只回列表需要的字段，正文不在这里传）——
/// 列表页不需要 200KB 正文，点进详情才 `localtask.get`。
class NxKvQueueView extends StatefulWidget {
  const NxKvQueueView({super.key, required this.controller});

  final NxKvController controller;

  @override
  State<NxKvQueueView> createState() => _NxKvQueueViewState();
}

class _NxKvQueueViewState extends State<NxKvQueueView> {
  kv.LocaltaskTasksOutput? _data;
  bool _loading = false;
  String? _error;

  /// 状态过滤：null = 全部。
  String? _filter;

  /// 正在把某条任务标完成（避免重复点）。
  int? _busyId;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
    _load();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    super.dispose();
  }

  void _onController() {
    if (!mounted) return;
    setState(() {});
    _load();
  }

  Future<void> _load() async {
    final key = widget.controller.selectedKey;
    if (key == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.controller.tasksOf(key, status: _filter);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = NxKvController.humanize(e);
        _loading = false;
      });
    }
  }

  Future<void> _claim() async {
    final topic = widget.controller.selected;
    if (topic == null) return;
    setState(() => _loading = true);
    try {
      final r = await widget.controller.claim(topic);
      if (!mounted) return;
      if (r.status == kv.LocaltaskClaimStatus.ok && r.taskId != null) {
        await widget.controller.refresh();
        if (!mounted) return;
        await _openTask(r.taskId!);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(r.status == kv.LocaltaskClaimStatus.blocked
                ? '这个主题的任务被依赖挡住了，先去完成上游'
                : '这个主题暂时没有可领的任务'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('领取失败：${NxKvController.humanize(e)}')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final topic = widget.controller.selected;
    if (topic == null) return;
    final md = await openMdComposer(
      context,
      title: '新建任务 · ${topic.name}',
      hint: '第一行写标题（# 开头），下面写背景/验收/约束。',
      initialText: '# \n\n## 背景\n\n\n## 验收\n\n- [ ] \n\n## 约束\n\n- \n',
      submitLabel: '派发任务',
      templates: const ['背景', '验收', '约束'],
    );
    if (md == null || md.trim().isEmpty) return;
    try {
      final r = await widget.controller.add(md, topic.cwd);
      await widget.controller.refresh();
      if (!mounted) return;
      await _openTask(r.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('派发失败：${NxKvController.humanize(e)}')),
      );
    }
  }

  Future<void> _openTask(int id) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => NxKvTaskDetailPage(
        controller: widget.controller,
        id: id,
        topicKey: widget.controller.selectedKey,
      ),
    ));
    if (!mounted) return;
    // 详情里可能标了完成 / 交了反馈 → 回来刷新队列与计数
    await widget.controller.refresh();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
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
      onRefresh: () async {
        await c.refresh();
        await _load();
      },
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          _topicStrip(c),
          const SizedBox(height: AppSpacing.sm),
          _actions(c),
          const SizedBox(height: AppSpacing.sm),
          _filters(),
          const SizedBox(height: AppSpacing.xs),
          if (_error != null)
            NxKvNotice(text: '这个主题的清单拉不到', detail: _error, actionLabel: '重试', onAction: _load, isError: true)
          else if (_loading && _data == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if ((_data?.tasks ?? const []).isEmpty)
            NxKvNotice(
              text: _filter == null ? '这个主题还没有任务' : '没有这个状态的任务',
              detail: _filter == null ? '点「新建」派一条，或等 agent 交活。' : null,
            )
          else
            ...(_data!.tasks.map((t) => _row(t, c.selectedKey))),
        ],
      ),
    );
  }

  /// 主题横条：一眼看到「哪个主题有活」，点一下切过去。
  Widget _topicStrip(NxKvController c) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: c.topics.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (_, i) {
          final t = c.topics[i];
          final on = t.key == c.selectedKey;
          return Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => c.select(t.key),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: on ? cs.primary : cs.outlineVariant,
                    width: on ? 1.4 : 1,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Text(
                      t.name,
                      style: TextStyle(
                        fontSize: 12,
                        color: on ? cs.primary : cs.onSurface,
                        fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    if (t.pending > 0) ...[
                      const SizedBox(width: 5),
                      Text('${t.pending}', style: TextStyle(fontSize: 10, color: on ? cs.primary : cs.outline)),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _actions(NxKvController c) {
    final t = c.selected;
    final canClaim = (t?.pending ?? 0) > 0;
    return Row(
      children: [
        FilledButton.icon(
          onPressed: canClaim && !_loading ? _claim : null,
          icon: const Icon(Icons.download_outlined, size: 16),
          label: Text(canClaim ? '领一条（${t!.pending}）' : '没有可领的'),
          style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
        ),
        const SizedBox(width: AppSpacing.xs),
        OutlinedButton.icon(
          onPressed: _create,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('新建'),
          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
        ),
        const Spacer(),
        if (_loading)
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
      ],
    );
  }

  Widget _filters() {
    const items = [
      (null, '全部'),
      ('pending', '待领'),
      ('claimed', '进行中'),
      ('done', '已完成'),
    ];
    return Row(
      children: [
        for (final (value, label) in items)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: ChoiceChip(
              label: Text(label, style: const TextStyle(fontSize: 11)),
              selected: _filter == value,
              visualDensity: VisualDensity.compact,
              onSelected: (_) {
                setState(() => _filter = value);
                _load();
              },
            ),
          ),
      ],
    );
  }

  Widget _row(kv.LocaltaskTasksTask t, String? key) {
    final cs = Theme.of(context).colorScheme;
    final busy = _busyId == t.id;
    return InkWell(
      onTap: () => _openTask(t.id),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs, horizontal: AppSpacing.xs),
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
            if (busy)
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            else if (t.status == 'pending')
              IconButton(
                tooltip: '领取',
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.play_arrow_outlined, color: cs.outline),
                onPressed: () async {
                  setState(() => _busyId = t.id);
                  try {
                    final topic = widget.controller.selected;
                    if (topic != null) await widget.controller.claim(topic);
                    await widget.controller.refresh();
                    await _load();
                  } finally {
                    if (mounted) setState(() => _busyId = null);
                  }
                },
              )
            else
              Icon(Icons.chevron_right, size: 16, color: cs.outline),
          ],
        ),
      ),
    );
  }
}
