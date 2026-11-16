/// 侧边栏的**行模型** —— 与 nx-kv 面板（`src/web/frontend/components/sidebar/model.ts`）
/// 同一套语义：**项目组是组、项目是项目，两者都是队列**。
///
/// ## 第 6 轮的修正（验收反馈：「当前和 nx-kv web 侧的语义完全不同」）
///
/// 上一版把组做成了「指向成员的指针」，点进去列成员项目、再点成员进队列 ——
/// 那仍然是**跳项目**。反馈原话三条，逐条对到本文件：
///
///   1. 「**项目组就是项目组**」—— 组有**自己的任务**（组任务）。判据只认任务正文
///      frontmatter 的 `board`（服务端 `localtask.boardtasks` 已按这个口径聚合好）。
///      组行的徽标 = 本组任务待领数，不是成员队列之和。
///   2. 「新建可以选择项目组下的绑定仓库」—— 在组里派活要挑一个**落点项目**：
///      任务物理上落进那个项目的队列（agent 按目录领活），归属写进 frontmatter。
///      所以组的成员表只用于「新建时选项目」，**不作为导航**。
///   3. 「项目就是项目」—— 项目行是项目队列；组任务从项目侧**剔除**
///      （面板的「两种走向」：`projectTasks` / `projectPending`）。
///   4. 「项目组的不要跳到项目去」—— 点组进的是组自己的清单，不是成员清单。
///
/// ## 两种走向的算术
///
/// 服务端 `localtask.list` 给的是**队列真相**（含组任务）。项目行的计数要减掉
/// 那些指向某个组的任务，而端侧只知道「每个组有哪些组任务、各自落在哪个队列」
/// （`boardtasks` 的 `topicKey`）。于是：
///
///     项目待领 = Σ(队列待领) − Σ(该队列里指向各组的待领)
///
/// 减法比加法可靠：组任务被漏算时最多是「项目侧多算」，不会把项目任务凭空抹掉。
///
/// ## 第 7 轮的补齐（反馈：「侧边栏的逻辑仍然不对 / 参考当前的 nx-kv 的侧边栏」）
///
/// 面板侧栏还有两处语义上一版没抄对，这轮收进行模型（UI 不再自己判）：
///
///   · **徽标口径**（[NxKvSideRow.badgeText]）：组行 = `pending > 0 ? pending : 成员数`
///     （面板 `.cnt` 同款）；项目行 = 有待领才画。上一版恒报 `pending/total`，
///     「0 条待领」被画成了和「没数」一样吵的东西；
///   · **谁是叶子**（[NxKvSideRow.hasChevron]）：组没有下一层，不画展开箭头；
///     项目行箭头只在多队列时出现。上一版给组行画了 `chevron_right` ——
///     「项目组的不要跳到项目去」的视觉残留，箭头本身就在暗示「还能钻进去」。
///
/// ## 第 8 轮：任务清单的显示序（反馈「时间最新的在最上面」）
///
/// 队列真相是**追加序**（`seq` = 发布先后 = agent 领取优先级），直接画就是
/// 「刚发的活在最底下」。[sortTasksForDisplay] 把显示序与队列序分开：
/// 待领取 → 已领取 → 已终态，桶内按「最近一次变化」倒序。与面板
/// `sortTasksForDisplay` 同构，仅一处刻意差异（面板待领取保队列序——它有
/// 拖动排序；手机没有，且本轮反馈明确要最新的在上面）。
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
/// 字段按 `kind` 选择性出现：组行带 [members]（新建任务时选项目用），
/// 项目行带 [queues]。
class NxKvSideRow {
  const NxKvSideRow({
    required this.kind,
    required this.id,
    required this.label,
    this.desc = '',
    this.hint = '',
    this.pending = 0,
    this.total = 0,
    this.statsKnown = true,
    this.repoKey = '',
    this.groupKey = '',
    this.groupId = '',
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

  /// 次要信息：项目 = 本机路径；组 = 「N 个绑定仓库」。
  final String hint;

  /// 待领数：组 = **本组任务**待领；项目 = **项目走向**待领（已剔除组任务）。
  final int pending;

  /// 任务总数（同口径）。
  final int total;

  /// 组行的计数是否真的拿到了。
  ///
  /// `boardtasks` 拉不到时是 false —— 那时 [pending]、[total] 都是 0，
  /// 但 0 的意思是「没有组任务」，不是「没数」，界面不能把两者画成一样。
  final bool statsKnown;

  /// 仓库键（`github.com/owner/name`）；纯本机目录 / 组行为空串。
  final String repoKey;

  /// 组键（`group/mobile`）；项目行为空串。
  final String groupKey;

  /// 看板 id（新建任务写进 frontmatter 的就是它）；项目行为空串。
  final String groupId;

  /// 组行的成员仓库键（**可能有本机没有队列的成员**，那类选不了落点）。
  final List<String> members;

  /// 项目行下的队列（服务端顺序，第一条是默认入口）。
  final List<kv.LocaltaskListTopic> queues;

  bool get isGroup => kind == NxKvRowKind.group;

  /// 点一下能切到哪条队列；null = 不是可直达的队列（组行 / 空项目）。
  String? get topicKey => queues.isEmpty ? null : queues.first.key;

  /// 有第二条队列才值得画展开箭头：单队列项目点行就是进队列。
  bool get expandable => queues.length > 1;

  int get memberCount => members.length;

  /// 行尾徽标写什么；null = 什么都不画。
  ///
  /// 口径与 nx-kv 面板 `.cnt` **逐字对齐**（`components/sidebar/index.tsx`）：
  ///
  ///   · 组行 = `pending > 0 ? pending : count` —— 组里有待领的活就报活，
  ///     一条都没有才报**成员数**（「这个组挂着几个仓库」）。组任务数是 0 时
  ///     报 0 没有信息量，这点与上一版「恒报 pending/total」不同。
  ///   · 项目行 = `pending > 0 ? pending : 不画` —— 项目侧的 0 更是噪音，
  ///     面板也是 `{row.pending > 0 && <span className="cnt">}`。
  ///
  /// 组行的数**拿不到**时（[statsKnown]=false）返回 `—`：说不清，比说 0 诚实。
  String? get badgeText {
    if (isGroup) {
      if (!statsKnown) return '—';
      return pending > 0 ? '$pending' : '$memberCount';
    }
    return pending > 0 ? '$pending' : null;
  }

  /// 徽标要不要用强调语气（主色底）：只有「有活待领」才配。
  bool get badgeEmphasized => pending > 0;

  /// 徽标的完整口径（长按 / hover 时说明「这个数字是什么」）。
  String get badgeHint {
    if (isGroup) {
      return statsKnown
          ? '组任务待领 $pending/$total · 成员 $memberCount 个'
          : '成员 $memberCount 个 · 组任务数暂时拿不到';
    }
    return '项目待领 $pending/$total';
  }

  /// 要不要画展开箭头。
  ///
  /// 面板里箭头是「就地展开子内容」；端侧能就地展开的只有**多队列项目**
  /// （队列是手机唯一的多队列入口，单队列点行就进去了）。组行是**叶子** ——
  /// 面板给它的 `tw` 是个空占位，不画假箭头（第 6 轮反馈「项目组的不要跳到
  /// 项目去」的视觉残留就是那颗箭头）。
  bool get hasChevron => !isGroup && queues.length > 1;

  /// 这一行（本项目）是否包含某条队列。
  bool contains(String topicKey) => queues.any((t) => t.key == topicKey);

  @override
  String toString() => isGroup
      ? 'group($label, 成员 $memberCount, 组任务待领 $pending/$total)'
      : 'repo($label, ${queues.length} 条队列, 项目待领 $pending)';
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

  /// 按组键（`group/xxx`）或看板 id 找组行 —— 抽屉选中态两种都认。
  NxKvSideRow? groupByKey(String? key) {
    if (key == null || key.isEmpty) return null;
    for (final r in rows) {
      if (r.isGroup && (r.groupKey == key || r.groupId == key)) return r;
    }
    return null;
  }

  /// 组视图里能当「新建落点」的项目（只看本机真的有队列的成员）。
  List<NxKvSideRow> membersOf(NxKvSideRow group) {
    final set = group.members.toSet();
    return rows.where((r) => !r.isGroup && set.contains(r.repoKey)).toList();
  }
}

/// 把扁平的主题清单铺成「组行 + 项目行」。
///
/// [boards] 空着也能跑：项目照常平铺，只是少了组那几行 —— 组信息是**导航装饰**，
/// 它丢了不该让侧边栏没得看。[boardTasks] 同理：拿不到时组行标 [statsKnown]=false，
/// 界面据此说「数暂时没有」，而不是报 0。
///
/// [query] 非空时只留命中的行：项目命中看名字/描述/路径/队列名；组命中看自己，
/// 或者**任一成员项目命中**（组是成员的指针，成员命中就算组命中）。
NxKvSideList buildSideList({
  required List<kv.LocaltaskListTopic> topics,
  List<NxKvBoard> boards = const [],
  List<kv.LocaltaskBoardTasksBoard> boardTasks = const [],
  bool boardTasksKnown = false,
  String query = '',
}) {
  // ── 1) 队列 → 项目 ────────────────────────────────────────
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

  // ── 2) 组任务 → 每条队列里「指向组」的那部分 ─────────────
  //
  // 判据与面板同款：任务的 board 归属由服务端聚合好（`localtask.boardtasks`），
  // 这里只按 topicKey 归位，不重复解析正文。
  final groupPendingByTopic = <String, int>{};
  final groupTotalByTopic = <String, int>{};
  for (final b in boardTasks) {
    for (final t in b.tasks) {
      groupTotalByTopic[t.topicKey] = (groupTotalByTopic[t.topicKey] ?? 0) + 1;
      if (t.status == 'pending') {
        groupPendingByTopic[t.topicKey] = (groupPendingByTopic[t.topicKey] ?? 0) + 1;
      }
    }
  }

  int projectPendingOf(List<kv.LocaltaskListTopic> ts) {
    var n = 0;
    for (final t in ts) {
      final group = groupPendingByTopic[t.key] ?? 0;
      final left = t.pending - group;
      n += left > 0 ? left : 0;
    }
    return n;
  }

  int projectTotalOf(List<kv.LocaltaskListTopic> ts) {
    var n = 0;
    for (final t in ts) {
      final group = groupTotalByTopic[t.key] ?? 0;
      final left = t.total - group;
      n += left > 0 ? left : 0;
    }
    return n;
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
        pending: projectPendingOf(b.topics),
        total: projectTotalOf(b.topics),
        queues: List.unmodifiable(b.topics),
      ),
  ];

  // 名字序，稳定：不按待领数抖 —— 手机屏幕小，抖一下人就找不到刚才那条了。
  repoRows.sort((a, b) => _byName(a.label, b.label));

  // ── 3) 看板 → 组行（有自己的组任务）────────────────────────
  final byRepoKey = <String, NxKvSideRow>{
    for (final r in repoRows)
      if (r.repoKey.isNotEmpty) r.repoKey: r,
  };

  // 组任务统计按「id / key / 名称」三样认：面板写 id，手写 frontmatter 可能是别的。
  kv.LocaltaskBoardTasksBoard? statsOf(NxKvBoard b) {
    for (final s in boardTasks) {
      if (s.id == b.id || s.key == b.key || s.name == b.name) return s;
    }
    return null;
  }

  final groupRows = <NxKvSideRow>[];
  for (final b in boards) {
    final stats = statsOf(b);
    groupRows.add(NxKvSideRow(
      kind: NxKvRowKind.group,
      id: 'g:${b.key}',
      groupKey: b.key,
      groupId: b.id,
      label: b.name,
      desc: b.desc,
      hint: '${b.repoKeys.length} 个绑定仓库',
      pending: stats?.pending ?? 0,
      total: stats?.total ?? 0,
      statsKnown: boardTasksKnown && stats != null,
      members: List.unmodifiable(b.repoKeys),
    ));
  }

  // ── 4) 搜索 ──────────────────────────────────────────────
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

// ─── 任务列表的显示序 ─────────────────────────────────────────────
//
// 反馈（fr #20）：「当前 task 排序反了，应该时间最新的在最上面；
// 未完成优先级 > 已领取 > 已完成」。
//
// 队列真相是**追加序**（`tasks.seq` = 发布先后，也是 agent 的领取优先级），
// 于是刚发布的那条活被压在几十条历史下面 —— 这就是「反了」的体感，与面板
// 2026-11-03 那次反馈同因（`modules/board/board-view.ts` 的 `sortTasksForDisplay`）。
//
// 两段式，与面板同构：
//   1. **分桶**：待领取 → 已领取 → 终态（已完成 / 已取消）。终态一律沉底；
//   2. **桶内最新在前**：取「这条任务最近一次变化的时刻」
//      （`completedAt → consumedAt → createdAt` 依次取第一个非空）倒序。
//
// 与面板的**一处刻意差异**：面板的待领取桶保「队列原序」（它支持拖动排序，
// 显示序 *就是* 领取优先级，动了就把优先级弄乱）。手机没有拖动，而本轮反馈
// 明确要求「最新的在最上面」，所以这里倒序 —— 领取优先级仍读得出来：
// 任务编号随发布递增，编号小的先被领。

/// 一条任务的显示序键：[bucket] 小的在前；同桶内 [stamp] 大的在前。
typedef NxKvTaskOrder = ({int bucket, String stamp, int id});

/// 状态 → 分桶。不认识的状态按终态处理（沉底），不会挤到待领取里冒充「还有活」。
int nxKvTaskBucket(String status) => switch (status) {
      'pending' => 0,
      'claimed' => 1,
      _ => 2,
    };

/// 「最近一次变化的时刻」。服务端给的是定宽本地时间串（`YYYY-MM-DD HH:mm:ss`），
/// 字典序即时间序，不必解析成 DateTime。
String nxKvTaskStamp({
  String createdAt = '',
  String consumedAt = '',
  String completedAt = '',
}) {
  if (completedAt.isNotEmpty) return completedAt;
  if (consumedAt.isNotEmpty) return consumedAt;
  return createdAt;
}

/// 按显示序排一份**新**列表（不改入参）。
///
/// [orderOf] 把各自的模型映射成 [NxKvTaskOrder]：项目任务
/// （`LocaltaskTasksTask`）与组任务（`LocaltaskBoardTasksBoardTask`）字段名不同，
/// 但排序口径必须只有一份 —— 否则两个列表的「最新」会各算各的。
List<T> sortTasksForDisplay<T>(List<T> list, NxKvTaskOrder Function(T) orderOf) {
  final out = List<T>.of(list);
  out.sort((a, b) {
    final ka = orderOf(a);
    final kb = orderOf(b);
    if (ka.bucket != kb.bucket) return ka.bucket - kb.bucket;
    final byStamp = kb.stamp.compareTo(ka.stamp); // 倒序：新的在前
    if (byStamp != 0) return byStamp;
    // 同一秒发布的两条：编号大的（后发的）在前；编号相同则保持调用方给的相对序
    return kb.id - ka.id;
  });
  return out;
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
