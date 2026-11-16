import 'package:flutter/material.dart';
import 'package:nx_kv_client/nx_kv_client.dart' as kv;

import '../../../../design_tokens/radius.dart';
import '../../../../design_tokens/spacing.dart';
import '../../../../api/mnws/nxkv/nxkv_controller.dart';
import '../../../../api/mnws/nxkv/nxkv_md.dart';
import '../../../../api/mnws/nxkv/nxkv_tree.dart';
import 'nxkv_motion.dart';
import 'nxkv_widgets.dart';

/// 抽屉：**换队列 / 换任务的地方**。
///
/// 装四件事：
///
///   1. **一棵树** —— 项目组行与项目行在**同一层**平铺（组在前、项目按名序），
///      没有「项目组 / 项目」两段标题：面板的侧栏就是一串行，组是行、项目也是行；
///   2. **搜索框** —— 同时过滤行与任务（组名 / 项目名 / 任务标题或编号）；
///   3. **动作** —— 新建（组里先选落点项目）+ 状态筛选；
///   4. **任务清单** —— 点一条就把主区切过去。
///
/// ## 组是叶子、项目是队列（对齐面板 `components/sidebar`）
///
///   - **组行不画展开箭头**：面板给组的 `tw` 是个空占位（`<span className="tw" />`），
///     因为它没有「下一层」。上一版在组行尾放了 `chevron_right`，看起来还能往下钻
///     ——那正是第 6 轮反馈「项目组的不要跳到项目去」留下的视觉残影；
///   - **项目行点一下就是进队列**（面板 `openRow` → `#/dir/<topicKey>`）；箭头只负责
///     **就地展开队列列表**，且只在多队列时出现（手机没有别的入口切队列）；
///   - **徽标口径照抄面板 `.cnt`**：组行 = 有活报活、没活报成员数；项目行 = 有活才画。
///     判定收在 `NxKvSideRow.badgeText` 里，界面不再自己算一遍。
///
/// ## 为什么没有「领一条」
///
/// 第 4 轮反馈第二条：「对于任务只标记完成，不要领任务的 btn」。手机是**验收端**：
/// 活由 PC 上的 agent 领走，人在这里看正文、标完成、提反馈。
///
/// ## 手感（第 2 轮 UI/UX 反馈）
///
/// 圆润图标（`*_rounded`）+ 图标底座（[NxKvIconTile]）+ 按压回弹（[NxKvPress]）
/// + 展开的 q 弹曲线（[NxKvMotion.snap]）。曲线与时长的道理写在 `nxkv_motion.dart`。
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
  final _searchFocus = FocusNode();

  /// 关键词（小写，比组名 / 项目名 / 队列名 / 任务标题与编号）。
  String _q = '';

  /// 搜索框有没有焦点（描边动画用）。
  bool _searchOn = false;

  /// 展开了队列的项目行 id。**按 id 记而不是按对象**：刷新后行是重建的，
  /// 记对象会让「刚展开的项目」在下一帧又折回去。
  final Set<String> _expanded = {};

  /// 上一次「自动展开了哪一行」。只在**选中项变了**的时候自动展开 ——
  /// 否则每次数据刷新都会把用户刚收起的那一行重新撑开，折叠键等于失灵。
  String? _expandedFor;

  /// 行高：44dp 是 iOS 列表的最小可点高度，比上一版的 32 好按得多。
  static const double _rowH = 44;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
    _searchFocus.addListener(() => setState(() => _searchOn = _searchFocus.hasFocus));
    _expandToSelection();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _searchFocus.dispose();
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
    if (host != null && host.hasChevron) _expanded.add(host.id);
  }

  /// 选中一条队列：抽屉留在原地（组和项目是并列的两个队列，不是父子）。
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
            stamp: nxKvTaskStamp(
              createdAt: t.createdAt,
              consumedAt: t.consumedAt,
              completedAt: t.completedAt,
            ),
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
            stamp: nxKvTaskStamp(
              createdAt: t.createdAt,
              consumedAt: t.consumedAt,
              completedAt: t.completedAt,
            ),
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
      // 右缘圆角 + 不铺满屏的白：抽屉是「一张浮起来的纸」，不是第五面墙
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(AppRadius.xxl)),
      ),
      backgroundColor: cs.surface,
      child: SafeArea(
        child: NxKvEnter(
          child: Column(
            children: [
              _head(cs, c),
              _searchRow(cs),
              _nav(cs, c),
              _actions(cs, c),
              Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.6)),
              Expanded(child: _list(cs, c)),
              Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.6)),
              _foot(cs, c),
            ],
          ),
        ),
      ),
    );
  }

  /// 顶部：这不是「某个 App 的首页」，而是「我连着哪台机器」。
  Widget _head(ColorScheme cs, NxKvController c) {
    final drift = c.drift != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.sm, AppSpacing.xxs),
      child: Row(
        children: [
          // 品牌点：一行小圆点比「nx-kv」四个字更快被认成一个 App 的身份
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            alignment: Alignment.center,
            child: Text(
              'nx',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: cs.primary, letterSpacing: -0.3),
            ),
          ),
          const SizedBox(width: 7),
          Text('nx-kv', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
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
          NxKvPress(
            onTap: widget.onOpenContract,
            semanticLabel: '契约状态',
            child: AnimatedContainer(
              duration: NxKvMotion.base,
              curve: NxKvMotion.soft,
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: (drift ? cs.error : cs.onSurfaceVariant).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: (drift ? cs.error : cs.outlineVariant).withValues(alpha: drift ? 0.55 : 0.8),
                ),
              ),
              child: Text(
                drift ? '契约过期' : '契约 ${c.localHash.length > 6 ? c.localHash.substring(0, 6) : c.localHash}',
                style: TextStyle(fontSize: 9, color: drift ? cs.error : cs.outline),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 搜索：iOS 搜索栏的样子（填充底、无框、聚焦才浮一圈细描边）。
  ///
  /// 用自绘容器而不是 `InputDecoration.border`：后者在高度变化时会出现
  /// 「框先变、字后变」的抖动。这里只有底色和描边在过渡（[NxKvMotion.soft]）。
  Widget _searchRow(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, 0, AppSpacing.sm, AppSpacing.xs),
      child: AnimatedContainer(
        duration: NxKvMotion.base,
        curve: NxKvMotion.soft,
        height: 38,
        padding: const EdgeInsets.only(left: 10, right: 4),
        decoration: BoxDecoration(
          color: _searchOn ? cs.surface : cs.onSurfaceVariant.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: _searchOn ? cs.primary.withValues(alpha: 0.35) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 17, color: _searchOn ? cs.primary : cs.outline),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _search,
                focusNode: _searchFocus,
                style: const TextStyle(fontSize: 13),
                cursorColor: cs.primary,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: '搜组 / 项目 / 任务',
                  hintStyle: TextStyle(fontSize: 12, color: cs.outline),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
                onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              ),
            ),
            AnimatedSize(
              duration: NxKvMotion.base,
              curve: NxKvMotion.glide,
              child: _q.isEmpty
                  ? const SizedBox.shrink()
                  : NxKvPress(
                      onTap: () {
                        _search.clear();
                        setState(() => _q = '');
                      },
                      scale: 0.9,
                      semanticLabel: '清空搜索',
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(Icons.close_rounded, size: 14, color: cs.outline),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 导航区：**一棵树**（组行在前、项目行在后），与面板侧栏同一形态。
  ///
  /// 没有两段标题：面板的侧栏就是一串行，靠图标与位置区分。手机上少两行标题
  /// 就多两条行的高度 —— 抽屉纵向还要留给任务清单。
  Widget _nav(ColorScheme cs, NxKvController c) {
    final list = c.sideList(query: _q);
    final maxHeight = (MediaQuery.sizeOf(context).height * 0.38).clamp(120.0, 320.0);

    final rows = <Widget>[];
    for (final r in list.rows) {
      if (r.isGroup) {
        rows.add(_groupRow(cs, c, r));
        continue;
      }
      final open = _q.isNotEmpty || _expanded.contains(r.id);
      rows.add(_repoRow(cs, c, r, open));
      // 队列子行：只在多队列时出现（单队列点行就进去了），展开动作带 q 弹
      if (r.hasChevron) {
        rows.add(AnimatedSize(
          duration: NxKvMotion.base,
          curve: NxKvMotion.glide,
          alignment: Alignment.topCenter,
          child: open
              ? Column(
                  children: [
                    for (final t in r.queues) _queueRow(cs, c, r, t),
                  ],
                )
              : const SizedBox(width: double.infinity),
        ));
      }
    }

    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
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
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        children: rows,
      ),
    );
  }

  /// 组行：**叶子**。
  ///
  /// 徽标口径：[NxKvSideRow.badgeText]（有活报活、没活报成员数、拿不到报 `—`）。
  /// 行尾**没有箭头** —— 组没有下一层，画箭头就是在暗示「点进去还有东西」。
  Widget _groupRow(ColorScheme cs, NxKvController c, NxKvSideRow g) {
    final on = c.selectedBoardKey == g.groupKey;
    return _tappable(
      onTap: () => widget.onBoard(g.groupKey),
      selected: on,
      semanticLabel: '${g.label}，${g.badgeHint}',
      child: Row(
        children: [
          // 与项目行的箭头槽同宽：留空是为了竖排对齐，不是为了画假箭头
          const SizedBox(width: 16),
          NxKvIconTile(
            icon: Icons.workspaces_rounded,
            color: on ? cs.primary : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              g.label.isEmpty ? '(未命名)' : g.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                height: 1.3,
                fontWeight: FontWeight.w600,
                color: on ? cs.primary : cs.onSurface,
              ),
            ),
          ),
          NxKvBadge(
            g.badgeText,
            emphasize: g.badgeEmphasized,
            tooltip: g.badgeHint,
          ),
          const SizedBox(width: 2),
        ],
      ),
    );
  }

  /// 项目行：点一下进队列，箭头展开多队列。
  Widget _repoRow(ColorScheme cs, NxKvController c, NxKvSideRow r, bool open) {
    final selected = r.contains(c.selectedKey ?? '');
    return _tappable(
      onTap: () {
        final key = r.topicKey;
        if (key != null) _go(key);
      },
      selected: selected,
      semanticLabel: '${r.label}，${r.badgeHint}',
      child: Row(
        children: [
          SizedBox(
            width: 16,
            child: r.hasChevron
                ? NxKvPress(
                    onTap: () => setState(() => open ? _expanded.remove(r.id) : _expanded.add(r.id)),
                    scale: 0.85,
                    semanticLabel: open ? '收起队列' : '展开队列',
                    child: NxKvChevron(open: open, size: 17, color: cs.outline),
                  )
                : null,
          ),
          NxKvIconTile(
            icon: Icons.folder_rounded,
            color: selected ? cs.primary : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              r.label.isEmpty ? '(未命名)' : r.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                height: 1.3,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? cs.primary : cs.onSurface,
              ),
            ),
          ),
          NxKvBadge(
            r.badgeText,
            emphasize: r.badgeEmphasized,
            tooltip: r.badgeHint,
          ),
          const SizedBox(width: 2),
        ],
      ),
    );
  }

  /// 队列子行：只在项目有多条队列时出现（单队列点项目本身就到这儿了）。
  Widget _queueRow(ColorScheme cs, NxKvController c, NxKvSideRow r, kv.LocaltaskListTopic t) {
    final selected = t.key == c.selectedKey;
    return Padding(
      padding: const EdgeInsets.only(left: 41, right: 0, bottom: 2),
      child: NxKvPress(
        onTap: () => _go(t.key),
        semanticLabel: '${t.name}，待领 ${t.pending} / ${t.total}',
        child: AnimatedContainer(
          duration: NxKvMotion.base,
          curve: NxKvMotion.soft,
          height: 38,
          padding: const EdgeInsets.only(left: 6, right: 8),
          decoration: BoxDecoration(
            color: selected ? cs.primary.withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Icon(
                Icons.subdirectory_arrow_right_rounded,
                size: 15,
                color: selected ? cs.primary : cs.outline,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  t.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: selected ? cs.primary : cs.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              // 队列行报「待领 / 总数」：它是一整条队列，总数在这里有意义
              NxKvBadge(
                t.pending > 0 ? '${t.pending}' : '${t.total}',
                emphasize: t.pending > 0,
                tooltip: '待领 ${t.pending} / 共 ${t.total}',
                fontSize: 9,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 行的共用外壳：高度、圆角、选中底、按压回弹，一处定义。
  Widget _tappable({
    required VoidCallback onTap,
    required bool selected,
    required Widget child,
    String? semanticLabel,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: NxKvPress(
        onTap: onTap,
        semanticLabel: semanticLabel,
        child: AnimatedContainer(
          duration: NxKvMotion.base,
          curve: NxKvMotion.soft,
          height: _rowH,
          padding: const EdgeInsets.only(left: 6, right: 8),
          decoration: BoxDecoration(
            color: selected ? cs.primary.withValues(alpha: 0.10) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: child,
        ),
      ),
    );
  }

  /// 一行动作：新建 + 状态筛选 —— 没有「领一条」：手机是验收端，不是干活端。
  Widget _actions(ColorScheme cs, NxKvController c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, 0, AppSpacing.sm, AppSpacing.xxs),
      child: Row(
        children: [
          NxKvPress(
            onTap: widget.onCreate,
            semanticLabel: '新建任务',
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                children: [
                  Icon(Icons.add_rounded, size: 16, color: cs.primary),
                  const SizedBox(width: 4),
                  Text('新建', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: cs.primary)),
                ],
              ),
            ),
          ),
          const Spacer(),
          _statusMenu(cs, c),
        ],
      ),
    );
  }

  /// 状态筛选收成一个胶囊菜单：四个 chip 常驻会把抽屉撑高一整行。
  Widget _statusMenu(ColorScheme cs, NxKvController c) {
    const items = <(String?, String)>[
      (null, '全部'),
      ('pending', '待领'),
      ('claimed', '进行中'),
      ('done', '已完成'),
    ];
    final active = c.statusFilter != null;
    final label = items.firstWhere((e) => e.$1 == c.statusFilter, orElse: () => (null, '全部')).$2;
    return PopupMenuButton<String?>(
      tooltip: '按状态筛选',
      initialValue: c.statusFilter,
      onSelected: c.filterTasks,
      itemBuilder: (_) => [
        for (final (value, text) in items)
          PopupMenuItem<String?>(
            value: value,
            height: 40,
            child: Row(
              children: [
                Icon(
                  value == c.statusFilter ? Icons.check_rounded : Icons.circle_outlined,
                  size: 14,
                  color: value == c.statusFilter ? cs.primary : cs.outlineVariant,
                ),
                const SizedBox(width: 8),
                Text(text, style: const TextStyle(fontSize: 12.5)),
              ],
            ),
          ),
      ],
      child: AnimatedContainer(
        duration: NxKvMotion.base,
        curve: NxKvMotion.soft,
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: active ? cs.primary.withValues(alpha: 0.10) : cs.onSurfaceVariant.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 11.5, color: active ? cs.primary : cs.outline, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 4),
            Icon(Icons.tune_rounded, size: 14, color: active ? cs.primary : cs.outline),
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
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
      itemCount: rows.length,
      itemBuilder: (_, i) => _taskRow(cs, c, rows[i]),
    );
  }

  Widget _taskRow(ColorScheme cs, NxKvController c, _TaskItem t) {
    final on = t.id == widget.currentId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: NxKvPress(
        onTap: () => widget.onPick(t.id, t.topicKey),
        semanticLabel: '任务 ${t.id}，${t.title}',
        child: AnimatedContainer(
          duration: NxKvMotion.base,
          curve: NxKvMotion.soft,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: on ? cs.primary.withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.title.isEmpty ? '(无标题)' : t.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: on ? cs.primary : cs.onSurface,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Text(
                    '#${t.id}',
                    style: TextStyle(
                      fontSize: 9.5,
                      color: cs.outline,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 5),
                  NxKvStatusTag(t.status),
                  if (t.round > 1) ...[
                    const SizedBox(width: 5),
                    Text('第${t.round}轮', style: TextStyle(fontSize: 9, color: cs.outline)),
                  ],
                  // 组任务：标出它物理上落在哪个项目（组页的「项目 tag」，与面板同取舍）
                  if (t.project != null) ...[
                    const SizedBox(width: 5),
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
                  Text(humanTime(t.stamp), style: TextStyle(fontSize: 9, color: cs.outline)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 底部：主题 / 契约 / 刷新 —— 低频入口，别占抽屉的黄金位置。
  Widget _foot(ColorScheme cs, NxKvController c) {
    Widget entry({required IconData icon, required String label, required VoidCallback onTap}) {
      return NxKvPress(
        onTap: onTap,
        semanticLabel: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 15, color: cs.outline),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(fontSize: 11, color: cs.outline)),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            entry(icon: Icons.layers_rounded, label: '主题', onTap: widget.onOpenTopics),
            entry(icon: Icons.verified_rounded, label: '契约', onTap: widget.onOpenContract),
            const Spacer(),
            NxKvPress(
              onTap: c.bootstrap,
              scale: 0.88,
              semanticLabel: '刷新主题与清单',
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(Icons.refresh_rounded, size: 17, color: cs.outline),
              ),
            ),
          ],
        ),
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
    required this.stamp,
    required this.topicKey,
    this.project,
  });

  final int id;
  final String title;
  final String status;
  final int round;

  /// 最近一次变化的时刻（完成/领取/入队，口径见 `nxKvTaskStamp`）——
  /// 列表按它倒序排，行上也画它，两处必须是同一把尺子。
  final String stamp;

  /// 这条任务物理落在哪个队列（组任务跨成员队列，不能拿当前选中项顶替）。
  final String topicKey;

  /// 组任务的归属项目名；项目任务为 null（不画 tag）。
  final String? project;
}
