import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/surround_game/engine/bfs_pathfinder.dart';
import 'package:xiaodouzi_fr/core/surround_game/surround_game_constants.dart';

/// 构造标准 9×9 四连通邻接表（参考 GameModel.swift:186-202）
List<Set<int>> _emptyAdjacency() {
  final adj = List.generate(81, (i) => <int>{});
  for (int i = 0; i < 81; i++) {
    final x = i % 9;
    final y = i ~/ 9;
    if (x > 0) adj[i].add(i - 1);     // 左
    if (x < 8) adj[i].add(i + 1);     // 右
    if (y > 0) adj[i].add(i - 9);     // 上
    if (y < 8) adj[i].add(i + 9);     // 下
  }
  return adj;
}

/// 构造 y=4 全行横墙隔断的邻接表
/// 每道横墙在 y=4，x 从 0 到 7，步长 2
/// 横墙切断 (baseId, baseId+9) 和 (baseId+1, baseId+10)
/// 注：x=0,2,4,6 覆盖 columns 0-7，x=7 覆盖 columns 7-8
///     6 块横墙完全封死 y=4 到 y=5 的通行
List<Set<int>> _fullBlockAdjacency() {
  final adj = _emptyAdjacency();
  // y=4, x=0,2,4,6 共 4 块横墙覆盖 columns 0-7
  for (int x = 0; x <= 6; x += 2) {
    final baseId = x + 4 * 9;
    adj[baseId].remove(baseId + 9);
    adj[baseId + 9].remove(baseId);
    adj[baseId + 1].remove(baseId + 10);
    adj[baseId + 10].remove(baseId + 1);
  }
  // x=7 横墙封 column 8
  final baseId7 = 7 + 4 * 9; // cellId=43
  adj[baseId7].remove(baseId7 + 9);
  adj[baseId7 + 9].remove(baseId7);
  adj[baseId7 + 1].remove(baseId7 + 10);
  adj[baseId7 + 10].remove(baseId7 + 1);
  return adj;
}

void main() {
  group('findShortestPath', () {
    test('空棋盘 top 在 (4,0) → 长度 9 (直走 8 步)', () {
      final adj = _emptyAdjacency();
      final path = BfsPathfinder.findShortestPath(adj, 4, true);
      expect(path.length, 9, reason: '空棋盘直走 8 步含起点共 9 节点');
      expect(path.first, 4, reason: '起点应保留');
      expect(path.last >= 72, true, reason: '终点必在 y=8 行');
      // 路径应为 [4, 13, 22, 31, 40, 49, 58, 67, 76]（直下）
      expect(path, [4, 13, 22, 31, 40, 49, 58, 67, 76]);
    });

    test('空棋盘 bottom 在 (4,8) → 长度 9 (直上 8 步)', () {
      final adj = _emptyAdjacency();
      final path = BfsPathfinder.findShortestPath(adj, 76, false);
      expect(path.length, 9);
      expect(path.first, 76);
      expect(path.last <= 8, true, reason: '终点必在 y=0 行');
      expect(path, [76, 67, 58, 49, 40, 31, 22, 13, 4]);
    });

    test('top 已在 y=8 (cellId=76) → 长度 1', () {
      final adj = _emptyAdjacency();
      final path = BfsPathfinder.findShortestPath(adj, 76, true);
      expect(path, [76], reason: '起点即终点');
    });

    test('全墙隔断 → 空列表', () {
      final adj = _fullBlockAdjacency();
      final path = BfsPathfinder.findShortestPath(adj, 4, true);
      expect(path, isEmpty, reason: 'y=4 全横墙阻断 top 到底线');
    });

    test('单道横墙在 y=4 仍能绕 → 非空且路径 > 9', () {
      final adj = _emptyAdjacency();
      // 只有 x=4 的一道横墙（不是全行阻断）
      final baseId = 4 + 4 * 9; // cellId = 40
      adj[baseId].remove(baseId + 9);
      adj[baseId + 9].remove(baseId);
      adj[baseId + 1].remove(baseId + 10);
      adj[baseId + 10].remove(baseId + 1);

      final path = BfsPathfinder.findShortestPath(adj, 4, true);
      expect(path, isNotEmpty, reason: '单一横墙可以绕');
      expect(path.length, greaterThan(9), reason: '绕路所以 > 9 步');
    });
  });

  group('hasPathToGoal', () {
    test('空棋盘 → true', () {
      expect(
        BfsPathfinder.hasPathToGoal(_emptyAdjacency(), 4, true),
        true,
      );
    });

    test('全隔断 → false', () {
      expect(
        BfsPathfinder.hasPathToGoal(_fullBlockAdjacency(), 4, true),
        false,
      );
    });
  });

  group('bothPlayersHavePath', () {
    test('空棋盘 → true', () {
      expect(
        BfsPathfinder.bothPlayersHavePath(_emptyAdjacency(), 4, 76),
        true,
      );
    });

    test('只阻断 top → false', () {
      expect(
        BfsPathfinder.bothPlayersHavePath(_fullBlockAdjacency(), 4, 76),
        false,
      );
    });

    test('bothPlayersHavePath: 双方都被阻断 → false', () {
      // _fullBlockAdjacency 在 y=4 放全行横墙阻断上下通透
      // top=72(y=8, 已到目标行) 不受影响 → hasPathToGoal=true
      // bottom=76(y=8, 需要走到 y=0) 被 y=4 横墙隔断 → hasPathToGoal=false
      // → bothPlayersHavePath=false
      final adj = _fullBlockAdjacency();
      expect(
        BfsPathfinder.bothPlayersHavePath(adj, 72, 76),
        false,
      );
    });
  });
}
