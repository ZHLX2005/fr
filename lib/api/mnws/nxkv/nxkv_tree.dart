/// 侧边栏的**行模型** —— 与 nx-kv 面板（`src/web/frontend/components/sidebar/model.ts`）
/// 同构：**项目组是入口（叶子），项目平铺（模块）**。
///
/// ## 为什么不是「组 → 项目 → 主题」的三级树
///
/// 第 4 轮我按「目录树」的字面意思铺了三层，第 5 轮验收反馈是「侧边栏的逻辑仍然
/// 不对，参考当前的 nx-kv 的侧边栏」。去读那张面板的模型才看清它 11-03 就改过语义：
///
///   - **组是操作单元，不是装项目的文件夹**。组行只是「指向成员的一根指针」，
///     点进去是组页；树里**不铺成员子行**。
///   - **仓库是独立模块**，一行一个，**永远不因为被某个组链接就消失**——
///     一个仓库挂在两个组里也只是同一条项目行，不会变成两份数据。
///   - 顺序是**稳定**的（用户排序 → 组序 → 名字），不按待领数抖动。
///
/// 三级树恰好把这三条全违反了：项目被塞进组里（换个组就找不到）、一个仓库同时
/// 属于两组时只能挂第一个（我当时的折中）、按待领数排序让整棵树每隔几秒换一次
/// 位置。手机上更糟 —— 屏幕小，抖一下就是「我刚才点的那个去哪了」。
///
/// ## 手机上「组页」是什么
///
/// PC 的组页列的是**组任务**（按 frontmatter 的 board 归属筛）。端侧契约
/// （`LocaltaskTasksTask`）里没有 board 字段，拿不到这个口径；所以手机上的组视图
/// 只做**导航**：本组有哪些项目、各自多少待领。不假称「本组任务」。
///
/// ## 进不来的队列
///
/// 没登记仓库的队列（纯本机目录）在 PC 侧栏里没有行 —— 它不属于任何仓库。
/// 手机不能照抄：抽屉是**唯一**入口，少一行就等于那条队列不可达。所以它们
/// 自己成一条项目行（身份 `dir:<topicKey>`），跟着一起按名字排。
///
/// 这个文件是**纯函数**（不碰 widget、不碰网络），`tool/nxkv_smoke.dart` 与
/// `test/api/mnws/nxkv_tree_test.dart` 直接喂数据验它。
library;

import 'package:nx_kv_client/nx_kv_client.dart' as kv;

import 'nxkv_boards.dart';

/// 行种类。UI 靠它决定图标、有没有展开箭头、点了去哪。
enum NxKvRowKind { group, repo }

/// 侧边栏的一行。
///
/// 字段按 `kind` 选择性出现：组行带 [members]，项目行带 [queues]。
class NxKvSideRow {
  const NxKvSideRow({
    required this.kind,
    required this.id,
    required this.label,
    this.desc = '',
    this.hint = '',
    this.pending = 0,
    this.total = 0,
    this.repoKey = '',
    this.groupKey = '',
    this.members = const [],
    this.queues = const [],
  });

  final NxKvRowKind kind;

  /// 稳定 id（展开态与选中态都按它记，不按对象）。
  final String id;

  /// 显示名（组名 / 项目名）。
  final String label;

  /// 组介绍 / 项目描述。
  final String desc;

  /// 次要信息：项目 = 本机路径；组 = 「N 个项目」。
  final String hint;

  /// 待领数：项目 = 本项目各队列之和；组 = 成员项目之和（**口径见文件头**）。
  final int pending;

  /// 任务总数（同口径）。
  final int total;

  /// 仓库键（`github.com/owner/name`）；纯本机目录为空串。
  final String repoKey;

  /// 组键（`group/mobile`）；项目行为空串。
  final String groupKey;

  /// 组行的成员仓库键（**可能有本机没有队列的成员**，那类不成行）。
  final List<String> members;

  /// 项目行下的队列（服务端顺序，第一条是默认入口）。
  final List<kv.LocaltaskListTopic> queues;

  bool get isGroup => kind == NxKvRowKind.group;

  /// 点一下能切到哪条队列；null = 不是可直达的队列（组行 / 空项目）。
  String? get topicKey => queues.isEmpty ? null : queues.first.key;

  /// 有第二条队列才值得画展开箭头：单队列项目点行就是进队列。
  bool get expandable => queues.length > 1;

  int get memberCount => members.length;

  /// 这一行（本项目）是否包含某条队列。
  bool contains(String topicKey) => queues.any((t) => t.key == topicKey);

  @override
  String toString() => isGroup
      ? 'group($label, ${memberCount} 个项目, 待领 $pending)'
      : 'repo($label, ${queues.length} 条队列, 待领 $pending)';
}

/// 一次构建的结果：渲染序的行 + 搜索命中数。
class NxKvSideList {
  const NxKvSideList({required this.rows, required this.matched});

  static const empty = NxKvSideList(rows: [], matched: 0);

  /// 渲染序：组行在前（看板顺序），项目行在后（名字序）。
  final List<NxKvSideRow> rows;

  /// 搜索命中数（0 = 没在搜）。
  final int matched;

  List<NxKvSideRow> get groups => rows.where((r) => r.isGroup).toList();

  List<NxKvSideRow> get repos => rows.where((r) => !r.isGroup).toList();

  /// 某条队列挂在哪一行下（抽屉据此自动展开）。
  NxKvSideRow? hostOf(String? topicKey) {
    if (topicKey == null || topicKey.isEmpty) return null;
    for (final r in rows) {
      if (r.contains(topicKey)) return r;
    }
    return null;
  }

  NxKvSideRow? groupByKey(String? key) {
    if (key == null || key.isEmpty) return null;
    for (final r in rows) {
      if (r.isGroup && r.groupKey == key) return r;
    }
    return null;
  }

  /// 组视图里要列的项目（只看本机真的有队列的成员）。
  List<NxKvSideRow> membersOf(NxKvSideRow group) {
    final set = group.members.toSet();
    return rows.where((r) => !r.isGroup && set.contains(r.repoKey)).toList();
  }
}

/// 把扁平的主题清单铺成「组行 + 项目行」。
///
/// [boards] 空着也能跑：项目照常平铺，只是少了组那几行 —— 组信息是**导航装饰**，
/// 它丢了不该让侧边栏没得看。
///
/// [query] 非空时只留命中的行：项目命中看名字/描述/路径/队列名；组命中看自己，
/// 或者**任一成员项目命中**（组是成员的指针，成员命中就算组命中）。
NxKvSideList buildSideList({
  required List<kv.LocaltaskListTopic> topics,
  List<NxKvBoard> boards = const [],
  String query = '',
}) {
  // ── 1) 队列 → 项目 ────────────────────────────────────────
  //
  // 一个仓库 = 一条项目行，它下面挂着自己的队列（服务端顺序，不重排：
  // 第一条是默认入口，重排会让「点开项目」这个动作每次都去别的地方）。
  final buckets = <String, _RepoBucket>{};
  for (final t in topics) {
    final repo = t.repo;
    final registered = repo != null && repo.key.isNotEmpty;
    final key = registered ? repo.key : 'dir:$t.key';
    final b = buckets.putIfAbsent(
      key,
      () => _RepoBucket(
        repoKey: registered ? repo.key : '',
        name: registered && repo.name.isNotEmpty ? repo.name : t.name,
        desc: registered ? (repo.desc ?? '') : '',
        path: t.cwd,
      ),
    );
    b.topics.add(t);
  }

  final repoRows = <NxKvSideRow>[
    for (final b in buckets.values)
      NxKvSideRow(
        kind: NxKvRowKind.repo,
        // 纯本机目录用第一条队列的 key 做身份：它没有仓库键可用，但必须稳定
        id: b.repoKey.isEmpty ? 'r:${b.topics.first.key}' : 'r:${b.repoKey}',
        repoKey: b.repoKey,
        label: b.name,
        desc: b.desc,
        hint: b.path,
        pending: b.topics.fold<int>(0, (n, t) => n + t.pending),
        total: b.topics.fold<int>(0, (n, t) => n + t.total),
        queues: List.unmodifiable(b.topics),
      ),
  ];

  // 名字序，稳定：不按待领数抖 —— 手机屏幕小，抖一下人就找不到刚才那条了。
  repoRows.sort((a, b) => _byName(a.label, b.label));

  // ── 2) 看板 → 组行（叶子）──────────────────────────────────
  final byRepoKey = <String, NxKvSideRow>{
    for (final r in repoRows)
      if (r.repoKey.isNotEmpty) r.repoKey: r,
  };

  final groupRows = <NxKvSideRow>[];
  for (final b in boards) {
    var pending = 0;
    var total = 0;
    for (final k in b.repoKeys) {
      final r = byRepoKey[k];
      if (r == null) continue; // 本机没队列的成员：只占成员数，不成行
      pending += r.pending;
      total += r.total;
    }
    groupRows.add(NxKvSideRow(
      kind: NxKvRowKind.group,
      id: 'g:${b.key}',
      groupKey: b.key,
      label: b.name,
      desc: b.desc,
      hint: '${b.repoKeys.length} 个项目',
      pending: pending,
      total: total,
      members: List.unmodifiable(b.repoKeys),
    ));
  }

  // ── 3) 搜索 ──────────────────────────────────────────────
  final q = query.trim().toLowerCase();
  if (q.isEmpty) {
    return NxKvSideList(rows: [...groupRows, ...repoRows], matched: 0);
  }

  bool repoHit(NxKvSideRow r) =>
      r.label.toLowerCase().contains(q) ||
      r.desc.toLowerCase().contains(q) ||
      r.hint.toLowerCase().contains(q) ||
      r.queues.any((t) => t.name.toLowerCase().contains(q) || t.key.toLowerCase().contains(q));

  bool groupHit(NxKvSideRow g) =>
      g.label.toLowerCase().contains(q) ||
      g.desc.toLowerCase().contains(q) ||
      g.members.any((k) {
        final r = byRepoKey[k];
        return r != null && repoHit(r);
      });

  final rows = [
    ...groupRows.where(groupHit),
    ...repoRows.where(repoHit),
  ];
  return NxKvSideList(rows: rows, matched: rows.length);
}

/// 名字序的「自然」比较：先小写比，完全一样再比原文（保证排序稳定）。
int _byName(String a, String b) {
  final d = a.toLowerCase().compareTo(b.toLowerCase());
  return d != 0 ? d : a.compareTo(b);
}

class _RepoBucket {
  _RepoBucket({
    required this.repoKey,
    required this.name,
    required this.desc,
    required this.path,
  });

  final String repoKey;
  final String name;
  final String desc;
  final String path;
  final List<kv.LocaltaskListTopic> topics = [];
}
