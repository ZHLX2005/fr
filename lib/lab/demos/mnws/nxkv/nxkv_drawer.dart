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
///   1. **行清单** —— 项目组（入口）+ 项目（平铺），与 nx-kv 面板同构；
///   2. **搜索框** —— 同时过滤行与任务（组名 / 项目名 / 任务标题或编号）；
///   3. **新建** —— 往当前队列派一条；
///   4. **任务清单** —— 点一条就把主区切过去，不再「返回队列再点」。
///
/// ## 为什么组不是「装着项目的文件夹」
///
/// 第 5 轮验收反馈：「侧边栏的逻辑仍然不对，参考当前的 nx-kv 的侧边栏」。
/// 第 4 轮那版是 组 → 项目 → 主题 的三级树，恰好是 nx-kv 在 11-03 明确改掉的形态：
///
///   - **组是操作单元**，点它是进组（看本组有哪些项目），不是展开一堆缩进的项目；
///   - **项目是模块**，永远平铺、永远在同一个位置 —— 一个项目挂在两个组里，
///     也不会变成两条数据、更不会因为「挂在第一个组里」就从别处消失；
///   - 顺序按名字，**不按待领数抖**：屏幕小，行一换位置人就找不到刚才那条。
///
/// ## 为什么没有「领一条」
///
/// 第 4 轮反馈第二条：「对于任务只标记完成，不要领任务的 btn」。手机是**验收端**：
/// 活由 PC 上的 agent 领走，人在这里看正文、标完成、提反馈。
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

  /// 关键词（小写，比组名 / 项目名 / 队列名 / 任务标题与编号）。
  String _q = '';

  /// 展开了队列的项目行 id。**按 id 记而不是按对象**：刷新后行是重建的，
  /// 记对象会让「刚展开的项目」在下一帧又折回去。
  final Set<String> _expanded = {};

  /// 正在看的组（组视图）；null = 平铺清单。
  String? _groupKey;

  /// 上一次「自动展开了哪一行」。只在**选中项变了**的时候自动展开 ——
  /// 否则每次数据刷新都会把用户刚收起的那一行重新撑开，折叠键等于失灵。
  String? _expandedFor;

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
    if (widget.controller.selectedKey != _expandedFor) _expandToSelection();
    setState(() {});
  }

  /// 展开到当前选中的那条队列（它挂在哪条项目行下就展开哪条）。
  void _expandToSelection() {
    final key = widget.controller.selectedKey;
    _expandedFor = key;
    final host = widget.controller.sideList().hostOf(key);
    if (host != null && host.expandable) _expanded.add(host.id);
  }

  /// 选中一条队列：退出组视图，回到平铺清单（那里能看到它被高亮）。
  void _go(String key) {
    setState(() => _groupKey = null);
    widget.onTopic(key);
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
            _nav(cs, c),
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

  /// 导航区：平铺清单，或（点了组之后）本组视图。
  ///
  /// 高度封顶（抽屉纵向还有任务清单要留位置），里面自己滚。搜索时不留折叠：
  /// 结果只有几条，折叠着等于藏起来。
  Widget _nav(ColorScheme cs, NxKvController c) {
    final list = c.sideList(query: _q);
    final group = list.groupByKey(_groupKey);
    final maxHeight = (MediaQuery.sizeOf(context).height * 0.34).clamp(96.0, 280.0);

    if (group != null) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
          children: _groupView(cs, c, list, group),
        ),
      );
    }

    final rows = <Widget>[];
    final groups = list.groups;
    final repos = list.repos;
    if (groups.isNotEmpty) {
      rows.add(_section(cs, '项目组', groups.length));
      for (final g in groups) {
        rows.add(_groupRow(cs, g));
      }
    }
    if (repos.isNotEmpty) {
      rows.add(_section(cs, '项目', repos.length));
      for (final r in repos) {
        final open = _q.isNotEmpty || _expanded.contains(r.id);
        rows.add(_repoRow(cs, c, r, open));
        if (open && r.queues.length > 1) {
          for (final t in r.queues) {
            rows.add(_queueRow(cs, c, r, t));
          }
        }
      }
    }

    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
        child: Text(
          _q.isNotEmpty ? '没有匹配「$_q」的组或项目' : '还没有任务队列',
          style: TextStyle(fontSize: 11, color: cs.outline),
        ),
      );
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

  /// 分段标题：手机上只有这一处能说明「上面那几行是组、下面这些是项目」。
  Widget _section(ColorScheme cs, String label, int count) {
    return Container(
      height: 26,
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 6, AppSpacing.sm, 0),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10, letterSpacing: 0.6, color: cs.outline, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 4),
          Text('$count', style: TextStyle(fontSize: 10, color: cs.outline.withValues(alpha: 0.7))),
        ],
      ),
    );
  }

  /// 组行：**叶子**。点一下进组视图（看本组有哪些项目、各多少待领）。
  ///
  /// 徽标口径：有待领就报成员队列之和，没有就报成员数 —— 与 nx-kv 面板同一取舍
  /// （那里 `pending > 0 ? pending : count`）。手机拿不到「组任务」口径
  /// （契约没 board 字段），所以长按说清这个数是**成员队列之和**。
  Widget _groupRow(ColorScheme cs, NxKvSideRow g) {
    return Tooltip(
      message: '${g.label} · ${g.memberCount} 个项目｜成员队列待领 ${g.pending}',
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        onTap: () => setState(() => _groupKey = g.groupKey),
        child: Container(
          height: 32,
          padding: const EdgeInsets.only(left: AppSpacing.xxs, right: AppSpacing.sm),
          child: Row(
            children: [
              const SizedBox(width: 14),
              Icon(Icons.folder_shared_outlined, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  g.label.isEmpty ? '(未命名)' : g.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, height: 1.3, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
                ),
              ),
              _badge(cs, pending: g.pending, total: g.memberCount, isCount: g.pending == 0),
              Icon(Icons.chevron_right, size: 14, color: cs.outline.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }

  /// 组视图：返回行 + 本组信息 + 成员项目（多队列的成员直接铺出队列）。
  List<Widget> _groupView(ColorScheme cs, NxKvController c, NxKvSideList list, NxKvSideRow g) {
    final members = list.membersOf(g);
    return [
      InkWell(
        onTap: () => setState(() => _groupKey = null),
        child: Container(
          height: 32,
          padding: const EdgeInsets.only(left: AppSpacing.xxs, right: AppSpacing.sm),
          child: Row(
            children: [
              Icon(Icons.arrow_back, size: 14, color: cs.primary),
              const SizedBox(width: 6),
              Text('返回', style: TextStyle(fontSize: 11, color: cs.primary)),
            ],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 2, AppSpacing.sm, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                g.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface),
              ),
            ),
            Text('${g.memberCount} 个项目', style: TextStyle(fontSize: 10, color: cs.outline)),
          ],
        ),
      ),
      if (g.desc.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 2, AppSpacing.sm, 4),
          child: Text(
            g.desc,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, height: 1.4, color: cs.outline),
          ),
        ),
      if (members.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 6, AppSpacing.sm, 6),
          child: Text(
            '这个组在本机还没有任务队列 —— 成员项目要到 PC 上登记并建队列',
            style: TextStyle(fontSize: 10, height: 1.4, color: cs.outline),
          ),
        )
      else
        for (final r in members) ...[
          _repoRow(cs, c, r, r.queues.length > 1),
          if (r.queues.length > 1)
            for (final t in r.queues) _queueRow(cs, c, r, t),
        ],
    ];
  }

  /// 项目行：点一下（单队列）进队列，（多队列）展开；右侧箭头总是能开合。
  Widget _repoRow(ColorScheme cs, NxKvController c, NxKvSideRow r, bool open) {
    final selected = r.contains(c.selectedKey ?? '');
    final badge = _badge(cs, pending: r.pending, total: r.total);
    return InkWell(
      onTap: () {
        if (r.expandable) {
          setState(() => open ? _expanded.remove(r.id) : _expanded.add(r.id));
        } else if (r.topicKey != null) {
          _go(r.topicKey!);
        }
      },
      child: Container(
        height: 32,
        padding: const EdgeInsets.only(left: AppSpacing.xxs, right: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? cs.primary.withValues(alpha: 0.06) : null,
          border: Border(left: BorderSide(color: selected ? cs.primary : Colors.transparent, width: 2)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              child: r.expandable
                  ? InkWell(
                      onTap: () => setState(() => open ? _expanded.remove(r.id) : _expanded.add(r.id)),
                      child: Icon(
                        open ? Icons.keyboard_arrow_down : Icons.chevron_right,
                        size: 14,
                        color: cs.outline,
                      ),
                    )
                  : null,
            ),
            Icon(
              selected ? Icons.folder : Icons.folder_outlined,
              size: 14,
              color: selected ? cs.primary : cs.outline,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                r.label.isEmpty ? '(未命名)' : r.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.3,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? cs.primary : cs.onSurface,
                ),
              ),
            ),
            badge,
          ],
        ),
      ),
    );
  }

  /// 队列子行：只在项目有多条队列时出现（单队列点项目本身就到这儿了）。
  Widget _queueRow(ColorScheme cs, NxKvController c, NxKvSideRow r, kv.LocaltaskListTopic t) {
    final selected = t.key == c.selectedKey;
    return InkWell(
      onTap: () => _go(t.key),
      child: Container(
        height: 28,
        padding: const EdgeInsets.only(left: AppSpacing.xxs + 20, right: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? cs.primary.withValues(alpha: 0.06) : null,
          border: Border(left: BorderSide(color: selected ? cs.primary : Colors.transparent, width: 2)),
        ),
        child: Row(
          children: [
            Icon(Icons.subdirectory_arrow_right, size: 13, color: selected ? cs.primary : cs.outline),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                t.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.3,
                  color: selected ? cs.primary : cs.onSurface,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            _badge(cs, pending: t.pending, total: t.total),
          ],
        ),
      ),
    );
  }

  /// 徽标：待领数（有就强调），否则总数；[isCount] 时是「成员数」那种纯数字。
  Widget _badge(ColorScheme cs, {required int pending, required int total, bool isCount = false}) {
    if (isCount) {
      return Text('$total', style: TextStyle(fontSize: 9, color: cs.outline));
    }
    if (pending > 0) {
      return Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: cs.primary.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text('$pending', style: TextStyle(fontSize: 9, color: cs.primary)),
      );
    }
    if (total > 0) return Text('$total', style: TextStyle(fontSize: 9, color: cs.outline));
    return const SizedBox.shrink();
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
