import 'package:flutter/material.dart';
import 'package:nx_kv_client/nx_kv_client.dart' as kv;

import '../../../../design_tokens/spacing.dart';
import '../../../../api/mnws/nxkv/nxkv_controller.dart';
import '../../../../api/mnws/nxkv/nxkv_md.dart';
import '../../../../api/mnws/nxkv/nxkv_tree.dart';
import 'nxkv_widgets.dart';

/// 抽屉：**换队列 / 换任务的地方**。
///
/// 装四件事：
///
///   1. **行清单** —— 项目组 + 项目，两段平铺；两者**都是队列**，点了就换主区；
///   2. **搜索框** —— 同时过滤行与任务（组名 / 项目名 / 任务标题或编号）；
///   3. **新建** —— 往当前队列派一条（在组里要先选落点项目）；
///   4. **任务清单** —— 点一条就把主区切过去，不再「返回队列再点」。
///
/// ## 组是组、项目是项目（第 6 轮验收反馈）
///
/// 反馈原文：「当前和 nx-kv web 侧的语义完全不同 / 项目组就是项目组 / 新建可以选择
/// 项目组下的绑定仓库 / 项目就是项目 / 项目组的不要跳到项目去」。
///
/// 上一版把组做成了「指向成员的指针」，点进去列成员、再点成员进队列 —— 那还是
/// 跳项目。现在按面板的现行语义来：
///
///   - **组有组自己的任务**（正文 frontmatter 的 board 归属），组行打开的是
///     「本组任务」清单，每条带归属项目 tag；
///   - **组的成员表只用于新建时选落点**，不是导航（`NxKvPage` 里那个选项目的弹窗）；
///   - **项目行是纯项目队列**：组任务从项目侧剔除（面板 `projectTasks` 同口径）；
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
    required this.onBoard,
    required this.onCreate,
    required this.onOpenTopics,
    required this.onOpenContract,
  });

  final NxKvController controller;

  /// 当前主区打开的任务（高亮用）；null = 停在队列。
  final int? currentId;

  /// 选一条任务：带上它物理落在哪条队列（组任务跨成员队列，不能拿当前选中项顶替）。
  final void Function(int id, String topicKey) onPick;

  /// 换主题队列：抽屉**不关**，好让人接着在这个主题里挑活。
  final void Function(String key) onTopic;

  /// 换到某个组（组队列）：组有组自己的任务，不跳到成员项目去。
  final void Function(String boardKey) onBoard;

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

  /// 选中一条队列：抽屉留在原地（组视图那种「返回上一层」的路径已经没有了 ——
  /// 组和项目是并列的两个队列，不是父子）。
  void _go(String key) {
    widget.onTopic(key);
  }

  /// 抽屉里那一列任务：组 → 组任务（带项目 tag），项目 → 项目走向的任务。
  ///
  /// 两种行共用一个轻量视图类型，是为了让「点开」这件事只有一份实现 ——
  /// 组任务的物理落点（topicKey）必须跟着它走，否则标完成/反馈会打错队列。
  List<_TaskItem> get _items {
    final c = widget.controller;
    final List<_TaskItem> all;
    if (c.selectedBoardKey != null) {
      all = [
        for (final t in c.groupTasks)
          _TaskItem(
            id: t.id,
            title: t.title,
            status: t.status,
            round: t.round,
            createdAt: t.createdAt,
            topicKey: t.topicKey,
            project: t.project,
          ),
      ];
    } else {
      final key = c.selectedKey ?? '';
      all = [
        for (final t in c.tasks)
          _TaskItem(
            id: t.id,
            title: t.title,
            status: t.status,
            round: t.round,
            createdAt: t.createdAt,
            topicKey: key,
          ),
      ];
    }
    if (_q.isEmpty) return all;
    return all.where((t) {
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

  /// 导航区：组 + 项目两段平铺。
  ///
  /// 高度封顶（抽屉纵向还有任务清单要留位置），里面自己滚。搜索时不留折叠：
  /// 结果只有几条，折叠着等于藏起来。
  Widget _nav(ColorScheme cs, NxKvController c) {
    final list = c.sideList(query: _q);
    final maxHeight = (MediaQuery.sizeOf(context).height * 0.34).clamp(96.0, 280.0);

    final rows = <Widget>[];
    final groups = list.groups;
    final repos = list.repos;
    if (groups.isNotEmpty) {
      rows.add(_section(cs, '项目组', groups.length));
      for (final g in groups) {
        rows.add(_groupRow(cs, c, g));
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
  /// 徽标口径：**本组任务**的待领数（不是成员队列之和 —— 那是上一版的错）。
  /// `boardtasks` 拉不到时报不出数，就退回成员数并说清「数暂时没有」，
  /// 绝不把「拿不到」画成「0 条」。
  Widget _groupRow(ColorScheme cs, NxKvController c, NxKvSideRow g) {
    final on = c.selectedBoardKey == g.groupKey;
    final hint = g.statsKnown
        ? '${g.label} · ${g.memberCount} 个绑定仓库｜组任务待领 ${g.pending}/${g.total}'
        : '${g.label} · ${g.memberCount} 个绑定仓库｜组任务数暂时拿不到（刷新试试）';
    return Tooltip(
      message: hint,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        onTap: () => widget.onBoard(g.groupKey),
        child: Container(
          height: 32,
          padding: const EdgeInsets.only(left: AppSpacing.xxs, right: AppSpacing.sm),
          decoration: BoxDecoration(
            color: on ? cs.primary.withValues(alpha: 0.06) : null,
            border: Border(left: BorderSide(color: on ? cs.primary : Colors.transparent, width: 2)),
          ),
          child: Row(
            children: [
              const SizedBox(width: 14),
              Icon(
                on ? Icons.folder_shared : Icons.folder_shared_outlined,
                size: 14,
                color: on ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  g.label.isEmpty ? '(未命名)' : g.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                    color: on ? cs.primary : cs.onSurfaceVariant,
                  ),
                ),
              ),
              if (g.statsKnown)
                _badge(cs, pending: g.pending, total: g.total)
              else
                Text('—', style: TextStyle(fontSize: 9, color: cs.outline)),
              Icon(Icons.chevron_right, size: 14, color: cs.outline.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
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

  /// 徽标：待领数（有就强调），否则总数 —— 项目侧与组侧口径都由行模型算好。
  Widget _badge(ColorScheme cs, {required int pending, required int total}) {
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
    final inGroup = c.selectedBoardKey != null;
    final rows = _items;
    if (rows.isEmpty) {
      return NxKvNotice(
        text: _q.isNotEmpty
            ? '没有匹配「$_q」的任务'
            : inGroup
                ? '这个组还没有任务'
                : '这个主题还没有任务',
        detail: _q.isNotEmpty ? '清空搜索换个词' : '点上面的「新建」派一条',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      itemCount: rows.length,
      itemBuilder: (_, i) => _taskRow(cs, c, rows[i]),
    );
  }

  Widget _taskRow(ColorScheme cs, NxKvController c, _TaskItem t) {
    final on = t.id == widget.currentId;
    return InkWell(
      onTap: () => widget.onPick(t.id, t.topicKey),
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
                // 组任务：标出它物理上落在哪个项目（组页的「项目 tag」，与面板同取舍）
                if (t.project != null) ...[
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      t.project!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 9, color: cs.primary.withValues(alpha: 0.8)),
                    ),
                  ),
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

/// 抽屉任务列的**统一行**：项目任务与组任务长得很像，但组任务多两样东西 ——
/// 物理落点（topicKey，标完成/反馈要用）与归属项目（组页的 tag）。
class _TaskItem {
  const _TaskItem({
    required this.id,
    required this.title,
    required this.status,
    required this.round,
    required this.createdAt,
    required this.topicKey,
    this.project,
  });

  final int id;
  final String title;
  final String status;
  final int round;
  final String createdAt;

  /// 这条任务物理落在哪个队列（组任务跨成员队列，不能拿当前选中项顶替）。
  final String topicKey;

  /// 组任务的归属项目名；项目任务为 null（不画 tag）。
  final String? project;
}
