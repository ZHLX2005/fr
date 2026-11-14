import 'package:flutter/material.dart';
import 'package:nx_kv_client/nx_kv_client.dart' as kv;

import '../../../../design_tokens/spacing.dart';
import 'nxkv_controller.dart';
import 'nxkv_md.dart';
import 'nxkv_widgets.dart';

/// 抽屉：**换任务的地方**。
///
/// 验收反馈的第二条是「增加抽屉侧边栏组件，通过侧边栏切换任务之类的，
/// 同时需要搜索框选取任务或者 picker topic」。所以这里装三件事：
///
///   1. **搜索框** —— 按标题或编号过滤当前主题的任务，敲两个字就能跳；
///   2. **topic picker** —— 主题一排按钮，点一下就换（换主题即换清单）；
///   3. **任务清单** —— 点一条就把主区切过去，不再「返回队列再点」。
///
/// 为什么任务清单要放抽屉而不是只放主页：手机上「看另一条」是最高频的动作，
/// 而它原来是三次点击（返回 → 找行 → 点）。抽屉把它压成一次。
class NxKvDrawer extends StatefulWidget {
  const NxKvDrawer({
    super.key,
    required this.controller,
    required this.currentId,
    required this.onPick,
    required this.onTopic,
    required this.onClaim,
    required this.onCreate,
    required this.onOpenTopics,
    required this.onOpenContract,
  });

  final NxKvController controller;

  /// 当前主区打开的任务（高亮用）；null = 停在队列。
  final int? currentId;

  /// 选一条任务（null = 回到队列，不带任务）。
  final void Function(int? id) onPick;

  /// 换主题：抽屉**不关**，好让人接着在这个主题里挑活。
  final void Function(String key) onTopic;
  final VoidCallback onClaim;
  final VoidCallback onCreate;
  final VoidCallback onOpenTopics;
  final VoidCallback onOpenContract;

  @override
  State<NxKvDrawer> createState() => _NxKvDrawerState();
}

class _NxKvDrawerState extends State<NxKvDrawer> {
  final _search = TextEditingController();

  /// 关键词（小写，比标题与编号）。
  String _q = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _search.dispose();
    super.dispose();
  }

  void _onController() {
    if (mounted) setState(() {});
  }

  List<kv.LocaltaskTasksTask> get _filtered {
    final list = widget.controller.tasks;
    if (_q.isEmpty) return list;
    return list.where((t) {
      if ('${t.id}' == _q) return true;
      return t.title.toLowerCase().contains(_q) || '${t.id}'.contains(_q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final cs = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final drawerW = (width * 0.86).clamp(280.0, 340.0);

    return Drawer(
      width: drawerW,
      child: SafeArea(
        child: Column(
          children: [
            _head(cs, c),
            _searchRow(cs),
            _topics(cs, c),
            _row(cs, c),
            Divider(height: 1, color: cs.outlineVariant),
            Expanded(child: _list(cs, c)),
            Divider(height: 1, color: cs.outlineVariant),
            _foot(cs, c),
          ],
        ),
      ),
    );
  }

  /// 顶部：这不是「某个 App 的首页」，而是「我连着哪台机器」。
  Widget _head(ColorScheme cs, NxKvController c) {
    final drift = c.drift != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.sm, AppSpacing.xxs),
      child: Row(
        children: [
          Text('nx-kv', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              '${c.target.pcName} · ${c.target.app}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: cs.outline),
            ),
          ),
          // 契约对不上就红点，点进去看差在哪
          InkWell(
            borderRadius: BorderRadius.circular(3),
            onTap: widget.onOpenContract,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                border: Border.all(color: drift ? cs.error : cs.outlineVariant),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                drift
                    ? '契约过期'
                    : '契约 ${c.localHash.length > 6 ? c.localHash.substring(0, 6) : c.localHash}',
                style: TextStyle(fontSize: 9, color: drift ? cs.error : cs.outline),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchRow(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, 0, AppSpacing.sm, AppSpacing.xxs),
      child: SizedBox(
        height: 36,
        child: TextField(
          controller: _search,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            hintText: '搜任务：标题或编号',
            hintStyle: TextStyle(fontSize: 12, color: cs.outline),
            prefixIcon: Icon(Icons.search, size: 16, color: cs.outline),
            prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            suffixIcon: _q.isEmpty
                ? null
                : InkWell(
                    onTap: () {
                      _search.clear();
                      setState(() => _q = '');
                    },
                    child: Icon(Icons.close, size: 14, color: cs.outline),
                  ),
            suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: cs.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: cs.outlineVariant),
            ),
          ),
          onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
        ),
      ),
    );
  }

  /// 主题选择器。横向滚动而不是下拉：主题就那么几个，一眼扫完比展开菜单快。
  Widget _topics(ColorScheme cs, NxKvController c) {
    if (c.topics.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        itemCount: c.topics.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xxs),
        itemBuilder: (_, i) {
          final t = c.topics[i];
          final on = t.key == c.selectedKey;
          return Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(5),
              onTap: () => widget.onTopic(t.key),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: on ? cs.primary : cs.outlineVariant,
                    width: on ? 1.3 : 1,
                  ),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  children: [
                    Text(
                      t.name,
                      style: TextStyle(
                        fontSize: 11,
                        color: on ? cs.primary : cs.onSurface,
                        fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    if (t.pending > 0) ...[
                      const SizedBox(width: 4),
                      Text('${t.pending}', style: TextStyle(fontSize: 9, color: on ? cs.primary : cs.outline)),
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

  /// 一行动作：领一条 / 新建 —— 与筛选挤在一行，省一屏空间。
  Widget _row(ColorScheme cs, NxKvController c) {
    final t = c.selected;
    final canClaim = (t?.pending ?? 0) > 0;
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          const SizedBox(width: AppSpacing.xs),
          TextButton.icon(
            onPressed: canClaim ? widget.onClaim : null,
            icon: const Icon(Icons.download_outlined, size: 15),
            label: Text(canClaim ? '领一条 ${t!.pending}' : '没活了', style: const TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
          TextButton.icon(
            onPressed: widget.onCreate,
            icon: const Icon(Icons.add, size: 15),
            label: const Text('新建', style: TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
          const Spacer(),
          _statusMenu(cs, c),
          const SizedBox(width: AppSpacing.xxs),
        ],
      ),
    );
  }

  /// 状态筛选收成一个菜单：四个 chip 常驻会把抽屉撑高一整行。
  Widget _statusMenu(ColorScheme cs, NxKvController c) {
    const items = <(String?, String)>[
      (null, '全部'),
      ('pending', '待领'),
      ('claimed', '进行中'),
      ('done', '已完成'),
    ];
    final label = items.firstWhere((e) => e.$1 == c.statusFilter, orElse: () => (null, '全部')).$2;
    return PopupMenuButton<String?>(
      tooltip: '按状态筛选',
      initialValue: c.statusFilter,
      onSelected: c.filterTasks,
      itemBuilder: (_) => [
        for (final (value, text) in items)
          PopupMenuItem<String?>(value: value, height: 36, child: Text(text, style: const TextStyle(fontSize: 12))),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: cs.outline)),
            Icon(Icons.filter_list, size: 14, color: cs.outline),
          ],
        ),
      ),
    );
  }

  Widget _list(ColorScheme cs, NxKvController c) {
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
    final rows = _filtered;
    if (rows.isEmpty) {
      return NxKvNotice(
        text: _q.isNotEmpty ? '没有匹配「$_q」的任务' : '这个主题还没有任务',
        detail: _q.isNotEmpty ? '清空搜索换个词' : '点上面的「新建」派一条',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      itemCount: rows.length,
      itemBuilder: (_, i) => _taskRow(cs, c, rows[i]),
    );
  }

  Widget _taskRow(ColorScheme cs, NxKvController c, kv.LocaltaskTasksTask t) {
    final on = t.id == widget.currentId;
    return InkWell(
      onTap: () => widget.onPick(t.id),
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.sm, 6, AppSpacing.sm, 6),
        decoration: BoxDecoration(
          color: on ? cs.primary.withValues(alpha: 0.06) : null,
          border: Border(left: BorderSide(color: on ? cs.primary : Colors.transparent, width: 2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.title.isEmpty ? '(无标题)' : t.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: on ? cs.primary : cs.onSurface,
                fontWeight: on ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 1),
            Row(
              children: [
                Text('#${t.id}', style: TextStyle(fontSize: 9, color: cs.outline)),
                const SizedBox(width: 4),
                NxKvStatusTag(t.status),
                if (t.round > 1) ...[
                  const SizedBox(width: 4),
                  Text('第${t.round}轮', style: TextStyle(fontSize: 9, color: cs.outline)),
                ],
                const Spacer(),
                Text(humanTime(t.createdAt), style: TextStyle(fontSize: 9, color: cs.outline)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 底部：主题 / 契约 / 刷新 —— 低频入口，别占抽屉的黄金位置。
  Widget _foot(ColorScheme cs, NxKvController c) {
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          const SizedBox(width: AppSpacing.xxs),
          TextButton(
            onPressed: widget.onOpenTopics,
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: Text('主题', style: TextStyle(fontSize: 11, color: cs.outline)),
          ),
          TextButton(
            onPressed: widget.onOpenContract,
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: Text('契约', style: TextStyle(fontSize: 11, color: cs.outline)),
          ),
          const Spacer(),
          IconButton(
            tooltip: '刷新主题与清单',
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.refresh, color: cs.outline),
            onPressed: c.bootstrap,
          ),
        ],
      ),
    );
  }
}
