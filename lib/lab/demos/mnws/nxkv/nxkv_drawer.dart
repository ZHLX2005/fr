import 'package:flutter/material.dart';
import 'package:nx_kv_client/nx_kv_client.dart' as kv;

import '../../../../design_tokens/spacing.dart';
import '../../../../api/mnws/nxkv/nxkv_controller.dart';
import '../../../../api/mnws/nxkv/nxkv_md.dart';
import '../../../../api/mnws/nxkv/nxkv_tree.dart';
import 'nxkv_widgets.dart';

/// 抽屉：**换任务的地方**。
///
/// 装四件事：
///
///   1. **目录树** —— 项目组 → 项目 → 主题（第 4 轮反馈第一条）；
///   2. **搜索框** —— 同时过滤树与任务（组名 / 项目名 / 任务标题或编号）；
///   3. **新建** —— 往当前队列派一条；
///   4. **任务清单** —— 点一条就把主区切过去，不再「返回队列再点」。
///
/// ## 为什么树取代了横向 chips
///
/// 第 4 轮反馈原文：「对于项目和项目组不要以侧边栏的滚动 tab 表示，应该用侧边栏
/// 目录树的结构表示」。chips 只能表达「一排队列」，表达不了「这条队列属于哪个
/// 仓库、那个仓库又属于哪个组」——三十个主题横着滚时，找「mobile 组的 fr」只能
/// 靠肉眼扫。树把这两层关系画出来，而且能折叠：不关心的大组收起来就不占地方。
///
/// ## 为什么没有「领一条」
///
/// 第 4 轮反馈第二条：「对于任务只标记完成，不要领任务的 btn」。手机是**验收端**：
/// 活由 PC 上的 agent 领走，人在这里看正文、标完成、提反馈。少一颗按钮，就少一次
/// 「手机上点一下把活抢走了，PC 上的 agent 反而没活干」。
class NxKvDrawer extends StatefulWidget {
  const NxKvDrawer({
    super.key,
    required this.controller,
    required this.currentId,
    required this.onPick,
    required this.onTopic,
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
  final VoidCallback onCreate;
  final VoidCallback onOpenTopics;
  final VoidCallback onOpenContract;

  @override
  State<NxKvDrawer> createState() => _NxKvDrawerState();
}

class _NxKvDrawerState extends State<NxKvDrawer> {
  final _search = TextEditingController();

  /// 关键词（小写，比组名 / 项目名 / 任务标题与编号）。
  String _q = '';

  /// 展开的节点 id。**按 id 记而不是按对象**：刷新后节点是重建的，
  /// 记对象会让「刚展开的组」在下一帧又折回去。
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
    _expandToSelection();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _search.dispose();
    super.dispose();
  }

  void _onController() {
    if (!mounted) return;
    _expandToSelection();
    setState(() {});
  }

  /// 展开到当前选中的队列（外加「一个都没展开时」把组都打开一层）。
  void _expandToSelection() {
    final c = widget.controller;
    final path = pathToKey(c.tree(), c.selectedKey ?? '');
    _expanded.addAll(path);
    if (_expanded.isEmpty) {
      for (final g in c.tree()) {
        _expanded.add(g.id);
      }
    }
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
            _tree(cs, c),
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
            hintText: '搜组 / 项目 / 任务',
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

  /// 目录树：组 → 项目 → 主题。
  ///
  /// 高度封顶（抽屉纵向还有任务清单要留位置），树自己滚。搜索时有命中的分支
  /// 自动全展开 —— 搜完还得手点三层才能看见结果，那等于没搜。
  Widget _tree(ColorScheme cs, NxKvController c) {
    final nodes = c.tree(query: _q);
    if (nodes.isEmpty) {
      if (_q.isNotEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
          child: Text('没有匹配「$_q」的组或项目', style: TextStyle(fontSize: 11, color: cs.outline)),
        );
      }
      return const SizedBox.shrink();
    }
    final maxHeight = (MediaQuery.sizeOf(context).height * 0.34).clamp(96.0, 280.0);
    final rows = <Widget>[];
    for (final n in nodes) {
      _flatten(n, 0, rows, cs, c, searching: _q.isNotEmpty);
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
        children: rows,
      ),
    );
  }

  void _flatten(
    NxKvTreeNode node,
    int depth,
    List<Widget> out,
    ColorScheme cs,
    NxKvController c, {
    required bool searching,
  }) {
    // 搜索时整棵铺开：结果只有几条，折叠着等于藏起来
    final open = searching || _expanded.contains(node.id);
    out.add(_treeRow(cs, c, node, depth, open));
    if (!open) return;
    for (final child in node.children) {
      _flatten(child, depth + 1, out, cs, c, searching: searching);
    }
  }

  Widget _treeRow(ColorScheme cs, NxKvController c, NxKvTreeNode node, int depth, bool open) {
    final selected = node.topicKey != null && node.topicKey == c.selectedKey;
    final indent = AppSpacing.xxs + depth * 14.0;
    final isGroup = node.level == NxKvTreeLevel.group;
    final isTopic = node.level == NxKvTreeLevel.topic;

    final label = Text(
      node.label.isEmpty ? '(未命名)' : node.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: isGroup ? 12 : (isTopic ? 11 : 12),
        height: 1.3,
        fontWeight: selected ? FontWeight.w600 : (isGroup ? FontWeight.w600 : FontWeight.w400),
        color: selected ? cs.primary : (isGroup ? cs.onSurfaceVariant : cs.onSurface),
      ),
    );

    final row = InkWell(
      // 能选中的点一下换队列；纯容器（多队列项目）点一下展开/收起
      onTap: () {
        if (node.selectable) {
          widget.onTopic(node.topicKey!);
        } else {
          setState(() => open ? _expanded.remove(node.id) : _expanded.add(node.id));
        }
      },
      child: Container(
        height: 30,
        padding: EdgeInsets.only(left: indent, right: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? cs.primary.withValues(alpha: 0.06) : null,
          border: Border(left: BorderSide(color: selected ? cs.primary : Colors.transparent, width: 2)),
        ),
        child: Row(
          children: [
            // 展开箭头：只有真的有子节点才画，其余留同宽空位对齐
            SizedBox(
              width: 14,
              child: node.expandable
                  ? InkWell(
                      onTap: () => setState(
                        () => open ? _expanded.remove(node.id) : _expanded.add(node.id),
                      ),
                      child: Icon(
                        open ? Icons.keyboard_arrow_down : Icons.chevron_right,
                        size: 14,
                        color: cs.outline,
                      ),
                    )
                  : null,
            ),
            Icon(
              isGroup
                  ? (open ? Icons.folder_open : Icons.folder_outlined)
                  : (isTopic ? Icons.subdirectory_arrow_right : Icons.inventory_2_outlined),
              size: 13,
              color: selected ? cs.primary : cs.outline,
            ),
            const SizedBox(width: 5),
            Expanded(child: label),
            if (node.pending > 0)
              Container(
                margin: const EdgeInsets.only(left: 4),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  border: Border.all(color: cs.primary.withValues(alpha: 0.6)),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text('${node.pending}', style: TextStyle(fontSize: 9, color: cs.primary)),
              )
            else if (node.total > 0)
              Text('${node.total}', style: TextStyle(fontSize: 9, color: cs.outline)),
          ],
        ),
      ),
    );
    return row;
  }

  /// 一行动作：新建 + 状态筛选 —— 没有「领一条」：手机是验收端，不是干活端。
  Widget _row(ColorScheme cs, NxKvController c) {
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          const SizedBox(width: AppSpacing.xs),
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
