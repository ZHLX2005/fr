/// BFS 寻路器 — 纯函数静态类
///
/// 职责：
///   1. 给定邻接表和起点，找最短路径到对方底线
///   2. 判定路径存在性（墙壁合法性的核心条件）
///
/// Swift 对应：GameAi.swift:226-266 pathForPlayer
///
/// 算法：标准 BFS + 父指针回溯
///   - 队列存 (cellId, parentIndex) — parentIndex 指向 logs 数组的索引
///   - 已访问标记用 List<(cellId, parent)> 的 logs
///   - 找到第一个满足"到达对方底线"的节点 → 回溯链
///
/// 性能：9×9 棋盘最坏 81 节点 + 平均度数 ≤ 4，单次 BFS < 0.1ms
class BfsPathfinder {
  BfsPathfinder._();

  /// BFS 内部的搜索节点
  @pragma('vm:prefer-inline')
  static const int _noParent = -1;

  /// 找从 start 到对方底线的最短路径
  ///
  /// [adjacency] 81 长度的邻接表
  /// [start]     起点 cellId（0-80）
  /// [isTopPlayer] true=上方玩家（目标 y=8，即 cellId ≥ 72）
  ///                false=下方玩家（目标 y=0，即 cellId ≤ 8）
  ///
  /// 返回路径（含 start 和终点），不可达返回空列表
  /// 路径保证最短（BFS 按层扩展，首次遇到终点即最短）
  ///
  /// Swift 参考：GameAi.swift:226-266 pathForPlayer
  static List<int> findShortestPath(
    List<Set<int>> adjacency,
    int start,
    bool isTopPlayer,
  ) {
    // 终点判定函数：top 玩家看 cellId >= 72 (y=8)
    // bottom 玩家看 cellId <= 8 (y=0)
    bool isGoal(int cellId) =>
        isTopPlayer ? cellId >= 72 : cellId <= 8;

    // 如果起点就是终点
    if (isGoal(start)) return [start];

    // logs 数组存 (cellId, parentIndex)
    // parentIndex 指向 logs 中父节点的索引，_noParent 表示根
    final logs = <_LogEntry>[];
    final queue = <int>[]; // 存索引到 logs

    logs.add(_LogEntry(data: start, parent: _noParent));
    queue.add(0); // 根节点在 logs[0]

    int head = 0; // 队列头指针（避免 removeFirst 的 O(n) 开销）

    // BFS 主循环
    while (head < queue.length) {
      final currentIndex = queue[head];
      head++;
      final current = logs[currentIndex];

      final neighbors = adjacency[current.data];
      for (final neighbor in neighbors) {
        if (isGoal(neighbor)) {
          // 找到终点 → 回溯路径
          final result = <int>[neighbor, current.data];
          int parent = current.parent;
          while (parent != _noParent) {
            result.add(logs[parent].data);
            parent = logs[parent].parent;
          }
          return result.reversed.toList();
        }

        // 未访问过
        if (!logs.any((e) => e.data == neighbor)) {
          logs.add(_LogEntry(data: neighbor, parent: currentIndex));
          queue.add(logs.length - 1);
        }
      }
    }

    return const []; // 不可达
  }

  /// 路径存在性检查（findShortestPath 的轻量封装）
  static bool hasPathToGoal(
    List<Set<int>> adjacency,
    int start,
    bool isTopPlayer,
  ) {
    return findShortestPath(adjacency, start, isTopPlayer).isNotEmpty;
  }

  /// 双方都能到达自己的终点（墙壁合法性校验的核心判定）
  ///
  /// 先用 BFS 检查 top 能否到 y=8，再检查 bottom 能否到 y=0。
  /// 只要有一方不可达即返回 false。
  ///
  /// Swift 参考：GameModel.swift:61-78 iWallIsAllow
  static bool bothPlayersHavePath(
    List<Set<int>> adjacency,
    int topPlayerId,
    int bottomPlayerId,
  ) {
    return hasPathToGoal(adjacency, topPlayerId, true) &&
        hasPathToGoal(adjacency, bottomPlayerId, false);
  }
}

/// BFS 内部日志条目
class _LogEntry {
  final int data;   // cellId
  final int parent; // logs 中的父节点索引

  const _LogEntry({required this.data, required this.parent});
}
