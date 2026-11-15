/// nx-kv 的**项目组**（看板）清单。
///
/// ## 为什么这里读原始 JSON
///
/// nx-kv 的跨语言契约（`contract/dart`）只声明了 10 条 action，看板（`/api/boards`）
/// 不在其中 —— 契约是「端侧要调什么」的白名单，不是服务端能力的全集。
/// 而手机端这张侧边栏要有「项目组」这一层（组行 + 组页）：缺了组名与成员表，
/// 组任务就没有归属可写、新建时也挑不了落点项目。
///
/// 所以这里做**唯一一处**契约外的读：路径固定、字段只取 `name/key/desc/repos`，
/// 解析失败一律退化成空列表（界面上就是「未分组」，不报错、不挡任务）。
/// nx-kv 哪天把 board.list 写进契约，这个文件整个可以删掉。
library;

/// 一个项目组（看板）。
///
/// 只留侧边栏用得上的四样：`id`（新建任务写 frontmatter）、稳定的 `key`
/// （`group/mobile` 这类）、给人看的 `name`、以及成员仓库的 key
/// （`github.com/owner/name`）—— 主题靠 `repo.key` 跟它对上，就能算出
/// 「这条队列属于哪些组」。
class NxKvBoard {
  const NxKvBoard({
    required this.id,
    required this.key,
    required this.name,
    this.desc = '',
    this.repoKeys = const [],
  });

  /// 看板 id（`b_xxx`）—— 新建组任务时写进 frontmatter 的就是它
  /// （面板「＋ 新增任务」写 id，CLI 手写可能给 key/名，服务端三样都认）。
  final String id;

  /// 看板键（`group/mobile`、`board/kv_fr`……）。
  final String key;

  /// 看板名（人写的那个）。
  final String name;

  /// 一句话说明（面板里的组介绍；手机上不展示，留着给搜索）。
  final String desc;

  /// 成员仓库 key。成员可以有「本机没登记」的占位项，那种没有 key，解析时跳过。
  final List<String> repoKeys;

  /// 从 `GET /api/boards` 的载荷里取出组清单。
  ///
  /// 兼容三种形状：`{ok:true,data:{boards:[…]}}`、`{boards:[…]}`、裸数组。
  /// 认不出来就返回空列表 —— 这一层不该因为服务端换了个信封就让侧边栏崩掉。
  static List<NxKvBoard> parse(Object? payload) {
    final list = _boardList(payload);
    final out = <NxKvBoard>[];
    for (final raw in list) {
      if (raw is! Map) continue;
      final key = _str(raw['key']);
      final name = _str(raw['name']);
      if (key.isEmpty && name.isEmpty) continue;
      out.add(NxKvBoard(
        id: _str(raw['id']),
        key: key.isEmpty ? name : key,
        name: name.isEmpty ? key : name,
        desc: _str(raw['desc']),
        repoKeys: _repoKeys(raw['repos']),
      ));
    }
    return out;
  }

  static List<Object?> _boardList(Object? payload) {
    Object? node = payload;
    if (node is Map) {
      node = node['data'] is Map ? (node['data'] as Map)['boards'] : node['boards'];
    }
    return node is List ? node : const [];
  }

  static List<String> _repoKeys(Object? raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    for (final m in raw) {
      if (m is! Map) continue;
      final k = _str(m['key']);
      // 占位成员（本机没登记、也没有远程地址）没有 key：它不属于任何主题
      if (k.isNotEmpty) out.add(k);
    }
    return out;
  }

  static String _str(Object? v) => v == null ? '' : '$v'.trim();

  @override
  String toString() => 'NxKvBoard($key, $name, ${repoKeys.length} repos)';
}
