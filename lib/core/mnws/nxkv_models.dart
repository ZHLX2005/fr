/// 被代理的 **nx-kv** 的数据形状。
///
/// ── 为什么单独一个文件 ────────────────────────────────────────────────────
/// 这不是 mn-ws 的模型，是**穿过桥之后**那个服务的模型。放在一起会让人
/// 以为 mn-ws 认识仓库、看板这些东西 —— 它不认识，它只是个管道。
/// 分开放，一眼就知道「谁是谁的形状」。
///
/// nx-kv 的响应是 `{ok:true, data:...}` 信封；mn-ws 自己的端点是字段平铺。
/// 两层信封在 fr 侧必须分开处理，不能用同一个解析器。
library;

/// nx-kv 的一个仓库登记。
class NxKvRepo {
  final String id;
  final String name;
  final String path;
  final String desc;
  final String notes;
  final String addedAt;
  final String updatedAt;

  /// 所属看板（单条查询与清单给的是同一份数据）
  final List<NxKvBoardRef> boards;

  const NxKvRepo({
    required this.id,
    required this.name,
    required this.path,
    required this.desc,
    required this.notes,
    required this.addedAt,
    required this.updatedAt,
    required this.boards,
  });

  factory NxKvRepo.fromJson(Map<String, dynamic> json) {
    final rawBoards = json['boards'];
    final boards = <NxKvBoardRef>[];
    if (rawBoards is List) {
      for (final b in rawBoards.whereType<Map<String, dynamic>>()) {
        boards.add(NxKvBoardRef.fromJson(b));
      }
    }
    return NxKvRepo(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      path: '${json['path'] ?? ''}',
      desc: '${json['desc'] ?? ''}',
      notes: '${json['notes'] ?? ''}',
      addedAt: '${json['addedAt'] ?? ''}',
      updatedAt: '${json['updatedAt'] ?? ''}',
      boards: boards,
    );
  }
}

/// 看板在仓库上的引用。
class NxKvBoardRef {
  final String id;
  final String name;
  final String desc;
  final String note;

  const NxKvBoardRef({
    required this.id,
    required this.name,
    required this.desc,
    required this.note,
  });

  factory NxKvBoardRef.fromJson(Map<String, dynamic> json) => NxKvBoardRef(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        desc: '${json['desc'] ?? ''}',
        note: '${json['note'] ?? ''}',
      );
}
