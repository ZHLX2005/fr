/// 侧边栏的**目录树**：项目组 → 项目 → 主题。
///
/// ## 为什么要树，而不是一排 chips
///
/// 第 4 轮验收反馈第一条：**「项目和项目组不要以侧边栏的滚动 tab 表示，应该用
/// 目录树的结构」**。原来的横向 chips 只能表达「一排主题」，表达不了两件更重要的
/// 事：这条队列属于**哪个仓库**、那个仓库又属于**哪个组**。三十个主题横着滚，
/// 找「mobile 组的 fr」只能靠肉眼扫，且永远看不出层级。
///
/// ## 三层的取舍
///
/// 树是三层，但**单队列项目会压成两层**：`fr` 这个仓库只有一条同名队列时，
/// 再画一个「fr → fr」的父子节点纯属浪费一屏空间 —— 那一层直接把项目节点做成
/// 可选中的叶子。只有「一个仓库有多条队列」时才真的展开第三层。
///
/// 这一层是**纯函数**（不碰 widget、不碰网络），`tool/nxkv_smoke.dart` 与
/// `test/api/mnws/nxkv_tree_test.dart` 都直接喂数据验它。
library;

import 'package:nx_kv_client/nx_kv_client.dart' as kv;

import 'nxkv_boards.dart';

/// 节点层级。UI 靠它决定缩进与字号，不靠字符串猜。
enum NxKvTreeLevel { group, project, topic }

/// 树上的一个节点。
class NxKvTreeNode {
  const NxKvTreeNode({
    required this.id,
    required this.label,
    required this.level,
    this.topicKey,
    this.hint = '',
    this.pending = 0,
    this.total = 0,
    this.children = const [],
  });

  /// 稳定 id（同一份数据每次构建都一样，用来记住展开状态）。
  final String id;

  /// 显示名（组名 / 仓库名 / 主题名）。
  final String label;

  final NxKvTreeLevel level;

  /// 选中它时要切到哪条队列；null = 只是个容器（项目节点）。
  final String? topicKey;

  /// 右侧的次要信息（项目节点的仓库 key、主题节点的目录）。
  final String hint;

  /// 子树里的待领数（含自己）。
  final int pending;

  /// 子树里的任务总数。
  final int total;

  final List<NxKvTreeNode> children;

  bool get selectable => topicKey != null;
  bool get expandable => children.isNotEmpty;

  /// 这棵子树里有没有 `topicKey` 这条队列（抽屉打开时用它自动展开到当前选中项）。
  bool contains(String key) =>
      topicKey == key || children.any((c) => c.contains(key));

  NxKvTreeNode copyWith({
    List<NxKvTreeNode>? children,
    int? pending,
    int? total,
  }) =>
      NxKvTreeNode(
        id: id,
        label: label,
        level: level,
        topicKey: topicKey,
        hint: hint,
        pending: pending ?? this.pending,
        total: total ?? this.total,
        children: children ?? this.children,
      );

  @override
  String toString() =>
      '${level.name}($label${topicKey == null ? '' : ' → $topicKey'}, $pending/$total)';
}

/// 没有归到任何看板时用的组名。
const String kUngroupedLabel = '未分组';

/// 把扁平的主题清单铺成三级树。
///
/// [boards] 空着也能跑：所有项目落到「未分组」下 —— 组信息是**装饰**，
/// 它丢了不该让侧边栏没得看。
///
/// [query] 非空时只留命中的分支（父节点命中就整棵留下，命中子节点就只留那条）。
List<NxKvTreeNode> buildTopicTree({
  required List<kv.LocaltaskListTopic> topics,
  List<NxKvBoard> boards = const [],
  String query = '',
}) {
  // 仓库 → 组：一个仓库可能在多个看板里，取**第一个**（服务端按创建顺序给）。
  // 手机上同一个项目挂在两个组下面只会让人怀疑「点了会不会是两份数据」。
  final boardOf = <String, NxKvBoard>{};
  for (final b in boards) {
    for (final key in b.repoKeys) {
      boardOf.putIfAbsent(key, () => b);
    }
  }

  final projects = <String, _ProjectBucket>{};
  for (final t in topics) {
    final repo = t.repo;
    final board = repo == null ? null : boardOf[repo.key];
    final groupKey = board?.key ?? '';
    final pid = repo != null ? repo.key : 'cwd:${t.cwd}';
    final bucket = projects.putIfAbsent(
      pid,
      () => _ProjectBucket(
        id: pid,
        name: repo?.name.isNotEmpty == true ? repo!.name : t.name,
        repoKey: repo?.key ?? '',
        groupKey: groupKey,
        groupName: board?.name ?? kUngroupedLabel,
      ),
    );
    bucket.topics.add(t);
  }

  // 组 → 项目
  final groups = <String, _GroupBucket>{};
  for (final p in projects.values) {
    final g = groups.putIfAbsent(
      p.groupKey,
      () => _GroupBucket(key: p.groupKey, name: p.groupName),
    );
    g.projects.add(p);
  }

  final out = <NxKvTreeNode>[];
  for (final g in groups.values) {
    final projectNodes = <NxKvTreeNode>[];
    for (final p in g.projects) {
      projectNodes.add(_projectNode(p));
    }
    projectNodes.sort(_byPendingThenName);
    out.add(NxKvTreeNode(
      id: 'g:${g.key}',
      label: g.name,
      level: NxKvTreeLevel.group,
      pending: projectNodes.fold(0, (n, p) => n + p.pending),
      total: projectNodes.fold(0, (n, p) => n + p.total),
      children: projectNodes,
    ));
  }
  // 有组名的排前面（组本身按名字），「未分组」垫底：它是兜底，不是入口
  out.sort((a, b) {
    final au = a.label == kUngroupedLabel;
    final bu = b.label == kUngroupedLabel;
    if (au != bu) return au ? 1 : -1;
    return a.label.toLowerCase().compareTo(b.label.toLowerCase());
  });

  if (query.trim().isEmpty) return out;
  final q = query.trim().toLowerCase();
  return out
      .map((n) => _filter(n, q))
      .whereType<NxKvTreeNode>()
      .toList();
}

/// 项目 → 节点。单队列且队列名就是仓库名时，压成一层可选中的节点。
NxKvTreeNode _projectNode(_ProjectBucket p) {
  final sorted = [...p.topics]..sort((a, b) {
      final d = b.pending.compareTo(a.pending);
      return d != 0 ? d : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

  final single = sorted.length == 1 && sorted.first.name == p.name;
  if (single) {
    final t = sorted.first;
    return NxKvTreeNode(
      id: 'p:${p.id}',
      label: p.name,
      level: NxKvTreeLevel.project,
      topicKey: t.key,
      hint: p.repoKey.isEmpty ? t.cwd : p.repoKey,
      pending: t.pending,
      total: t.total,
    );
  }

  final children = [
    for (final t in sorted)
      NxKvTreeNode(
        id: 't:${t.key}',
        label: t.name,
        level: NxKvTreeLevel.topic,
        topicKey: t.key,
        hint: t.cwd,
        pending: t.pending,
        total: t.total,
      ),
  ];
  return NxKvTreeNode(
    id: 'p:${p.id}',
    label: p.name,
    level: NxKvTreeLevel.project,
    hint: p.repoKey,
    pending: children.fold(0, (n, c) => n + c.pending),
    total: children.fold(0, (n, c) => n + c.total),
    children: children,
  );
}

/// 从根到「包含 [key] 的那个节点」的 id 路径（含末端）。
///
/// 抽屉打开时要自动展开到当前选中的队列 —— 否则树一多，用户看到的是一片
/// 折叠起来的组名，还得自己一层层点开去找「我刚才在看哪条」。
List<String> pathToKey(List<NxKvTreeNode> nodes, String key, [List<String> prefix = const []]) {
  for (final n in nodes) {
    final here = [...prefix, n.id];
    if (n.topicKey == key) return here;
    if (n.children.isNotEmpty) {
      final deeper = pathToKey(n.children, key, here);
      if (deeper.isNotEmpty) return deeper;
    }
  }
  return const [];
}

/// 搜索过滤：命中自己就整棵留下，否则只留命中的子树。
NxKvTreeNode? _filter(NxKvTreeNode node, String q) {
  final selfHit = node.label.toLowerCase().contains(q) ||
      node.hint.toLowerCase().contains(q) ||
      (node.topicKey?.toLowerCase().contains(q) ?? false);
  if (selfHit) return node;
  final kids = node.children
      .map((c) => _filter(c, q))
      .whereType<NxKvTreeNode>()
      .toList();
  if (kids.isEmpty) return null;
  return node.copyWith(
    children: kids,
    pending: kids.fold<int>(0, (n, c) => n + c.pending),
    total: kids.fold<int>(0, (n, c) => n + c.total),
  );
}

int _byPendingThenName(NxKvTreeNode a, NxKvTreeNode b) {
  final d = b.pending.compareTo(a.pending);
  return d != 0 ? d : a.label.toLowerCase().compareTo(b.label.toLowerCase());
}

class _ProjectBucket {
  _ProjectBucket({
    required this.id,
    required this.name,
    required this.repoKey,
    required this.groupKey,
    required this.groupName,
  });

  final String id;
  final String name;
  final String repoKey;
  final String groupKey;
  final String groupName;
  final List<kv.LocaltaskListTopic> topics = [];
}

class _GroupBucket {
  _GroupBucket({required this.key, required this.name});

  final String key;
  final String name;
  final List<_ProjectBucket> projects = [];
}
