import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/surround_game/engine/game_engine.dart';
import 'package:xiaodouzi_fr/core/surround_game/engine/bfs_pathfinder.dart';
import 'package:xiaodouzi_fr/core/surround_game/models/game_state.dart';
import 'package:xiaodouzi_fr/core/surround_game/surround_game_constants.dart';
import '_fixtures.dart';

void main() {
  group('初始化与基础', () {
    test('initialize → top=4, bottom=76, status=running, currentPlayerIsTop=true', () {
      final state = QuoridorEngine.initialize();
      expect(state.topPlayerId, 4, reason: 'top 起始 x=4,y=0 → id=4');
      expect(state.bottomPlayerId, 76, reason: 'bottom 起始 x=4,y=8 → id=76');
      expect(state.currentPlayerIsTop, true);
      expect(state.status, GameStatus.running);
      expect(state.topWallsPlaced, 0);
      expect(state.bottomWallsPlaced, 0);
      expect(state.history, isEmpty);
      expect(state.validMoves, isNotEmpty, reason: '初始有可走格子');
    });

    test('buildInitialAdjacency → 角点度数 2, 边格 3, 中心 4', () {
      final adj = QuoridorEngine.buildInitialAdjacency();
      // 角点 (0,0) cellId=0
      expect(adj[0].length, 2, reason: '0,0 只连右和下');
      expect(adj[0].contains(1), true);
      expect(adj[0].contains(9), true);
      // 边格 (4,0) cellId=4
      expect(adj[4].length, 3, reason: '4,0 连左、右、下');
      expect(adj[4].contains(3), true);
      expect(adj[4].contains(5), true);
      expect(adj[4].contains(13), true);
      // 中心 (4,4) cellId=40
      expect(adj[40].length, 4, reason: '4,4 连上下左右');
      expect(adj[40].contains(39), true); // 左
      expect(adj[40].contains(41), true); // 右
      expect(adj[40].contains(31), true); // 上
      expect(adj[40].contains(49), true); // 下
    });

    test('wallBaseId', () {
      // wallBaseId(0,0) = (0*2+1)+(0*2+1)*17 = 1+17 = 18
      expect(QuoridorEngine.wallBaseId(0, 0), 18);
      // wallBaseId(7,7) = (7*2+1)+(7*2+1)*17 = 15+15*17 = 15+255 = 270
      expect(QuoridorEngine.wallBaseId(7, 7), 270);
      // wallBaseId(3,4) = (3*2+1)+(4*2+1)*17 = 7+153 = 160
      expect(QuoridorEngine.wallBaseId(3, 4), 160);
    });

    test('wallOccupiedCells 横墙 (3,4) = [159, 160, 161]', () {
      final cells = QuoridorEngine.wallOccupiedCells(3, 4, WallOrientation.horizontal);
      expect(cells, [159, 160, 161], reason: 'base=160, horizontal=[-1, 0, +1]');
    });

    test('wallOccupiedCells 竖墙 (3,4) = [143, 160, 177]', () {
      final cells = QuoridorEngine.wallOccupiedCells(3, 4, WallOrientation.vertical);
      expect(cells, [143, 160, 177], reason: 'base=160, vertical=[-17, 0, +17]');
    });
  });

  group('走棋', () {
    test('top 向下走 (4→13) → topPlayerId 更新', () {
      var state = QuoridorEngine.initialize();
      state = QuoridorEngine.movePiece(state, 13)!;
      expect(state.topPlayerId, 13, reason: 'top 向下走一步');
      // 不触发自动换手（currentPlayerIsTop 不变）
      expect(state.currentPlayerIsTop, true);
    });

    test('top 走到无效格子 → 返回 null', () {
      final state = QuoridorEngine.initialize();
      final result = QuoridorEngine.movePiece(state, 76); // bottom 位置，无效
      expect(result, isNull);
    });

    test('走棋后 history 长度 +1', () {
      var state = QuoridorEngine.initialize();
      state = QuoridorEngine.movePiece(state, 13)!;
      expect(state.history.length, 1);
      expect(state.history[0].isWall, false);
      expect(state.history[0].isTopPlayer, true);
    });

    test('走棋后不自动换手', () {
      var state = QuoridorEngine.initialize();
      state = QuoridorEngine.movePiece(state, 13)!;
      expect(state.currentPlayerIsTop, true,
          reason: 'movePiece 不翻转 currentPlayerIsTop');
    });
  });

  group('跳跃', () {
    test('top (4,3), bottom (4,4) → validMoves 含 (4,5)', () {
      // 构造：top 在 cellId=31(x=4,y=3), bottom 在 cellId=40(x=4,y=4)
      // top 的邻接包含 40(=bottom), 应跳过到底线侧 cellId=49(x=4,y=5)
      final state = QuoridorEngine.fromBoardSpec(
        topPlayerId: 31,
        bottomPlayerId: 40,
        currentPlayerIsTop: true,
      );
      final topMoves = QuoridorEngine.getValidMoves(
        state.adjacency, 31, 40,
      );
      expect(topMoves.contains(49), true,
          reason: 'top 应跳过 bottom 到 (4,5)=49');
    });

    test('top (4,3), bottom 不相邻 → 仅四邻接', () {
      final state = QuoridorEngine.fromBoardSpec(
        topPlayerId: 31,
        bottomPlayerId: 76,
        currentPlayerIsTop: true,
      );
      final topMoves = QuoridorEngine.getValidMoves(
        state.adjacency, 31, 76,
      );

      // 不相邻，正确移动
      // top 在 31(y=3)，邻接 30(left), 32(right), 22(up), 40(down)
      // 没有跳跃
      expect(topMoves.length, 4, reason: '无跳跃时四格可走');
      expect(topMoves, containsAll([30, 32, 22, 40]));
    });
  });

  group('换手', () {
    test('switchTurn 翻转 currentPlayerIsTop 并重算 validMoves', () {
      var state = QuoridorEngine.initialize();
      // 初始 currentPlayerIsTop=true (top)
      // top 的 validMoves 包含 13(down), 3(left), 5(right)
      state = QuoridorEngine.switchTurn(state);

      expect(state.currentPlayerIsTop, false, reason: '翻转为 bottom 回合');
      expect(state.validMoves, isNotEmpty, reason: 'bottom 也有可走格');
      // bottom 在 cellId=76(y=8), 可走上、左、右
      // bottom 的邻接: 67(up), 75(left), 77(right)
    });

    test('switchTurn 不修改棋子位置和墙壁数', () {
      var state = QuoridorEngine.initialize();
      state = QuoridorEngine.switchTurn(state);

      expect(state.topPlayerId, 4);
      expect(state.bottomPlayerId, 76);
      expect(state.topWallsPlaced, 0);
      expect(state.bottomWallsPlaced, 0);
    });
  });

  group('邻接表更新', () {
    test('横墙 (0,0) → 切断 (0,9) 和 (1,10)', () {
      final adj = QuoridorEngine.buildInitialAdjacency();
      final result = QuoridorEngine.applyWallToAdjacency(
        adj, 0, 0, WallOrientation.horizontal, true,
      );
      expect(result[0].contains(9), false, reason: '0→9 切断');
      expect(result[9].contains(0), false, reason: '9→0 切断');
      expect(result[1].contains(10), false, reason: '1→10 切断');
      expect(result[10].contains(1), false, reason: '10→1 切断');
      // 没有意外切断
      expect(result[0].contains(1), true, reason: '0→1 仍在');
    });

    test('竖墙 (0,0) → 切断 (0,1) 和 (9,10)', () {
      final adj = QuoridorEngine.buildInitialAdjacency();
      final result = QuoridorEngine.applyWallToAdjacency(
        adj, 0, 0, WallOrientation.vertical, true,
      );
      expect(result[0].contains(1), false, reason: '0→1 切断');
      expect(result[1].contains(0), false, reason: '1→0 切断');
      expect(result[9].contains(10), false, reason: '9→10 切断');
      expect(result[10].contains(9), false, reason: '10→9 切断');
      // 没有意外切断
      expect(result[0].contains(9), true, reason: '0→9 仍在');
    });

    test('applyWallToAdjacency isPlacing=false → 完美恢复', () {
      final adj = QuoridorEngine.buildInitialAdjacency();
      final cut = QuoridorEngine.applyWallToAdjacency(
        adj, 3, 4, WallOrientation.horizontal, true,
      );
      final restored = QuoridorEngine.applyWallToAdjacency(
        cut, 3, 4, WallOrientation.horizontal, false,
      );
      // 和原始比较
      for (int i = 0; i < 81; i++) {
        expect(restored[i], adj[i], reason: 'node $i 恢复一致');
      }
    });
  });

  // ═══════════════════════════════════════════════════════
  // P4b 阶段追加：放墙 + 胜负
  // ═══════════════════════════════════════════════════════
  group('放墙', () {
    test('空棋盘横墙 (3,4) → 合法：wallGrid 三格占用', () {
      final state = QuoridorEngine.initialize();
      final result = QuoridorEngine.placeWall(state, 3, 4, WallOrientation.horizontal);
      expect(result, isNotNull);
      expect(result!.wallGrid[159], true, reason: 'base=160, 左格');
      expect(result.wallGrid[160], true, reason: '中心格');
      expect(result.wallGrid[161], true, reason: '右格');
    });

    test('同位置再放 → 重叠不合法 → null', () {
      var state = QuoridorEngine.initialize();
      state = QuoridorEngine.placeWall(state, 3, 4, WallOrientation.horizontal)!;
      final result = QuoridorEngine.placeWall(state, 3, 4, WallOrientation.horizontal);
      expect(result, isNull, reason: '墙壁重叠非法');
    });

    test('横墙叉竖墙（共享中心格 160）→ 不合法', () {
      var state = QuoridorEngine.initialize();
      state = QuoridorEngine.placeWall(state, 3, 4, WallOrientation.horizontal)!;
      // 竖墙 (3,4) 也占用 160
      final result = QuoridorEngine.placeWall(state, 3, 4, WallOrientation.vertical);
      expect(result, isNull, reason: '共享中心格 160');
    });

    test('把 top 完全封死 → 不合法', () {
      // top 在 cellId=0 (角落)
      // 横墙 (0,0): 切断 (0,9) 和 (1,10)
      // 竖墙 (0,0): 切断 (0,1) 和 (9,10)
      // 横墙后 top 还能从 0→1 绕路出去，再加竖墙则 0→1 也被切断 → top 被困
      var state = QuoridorEngine.fromBoardSpec(
        topPlayerId: 0,
        bottomPlayerId: 76,
        currentPlayerIsTop: true,
      );
      // 先放横墙 (合法)
      state = QuoridorEngine.placeWall(state, 0, 0, WallOrientation.horizontal)!;
      // 再放竖墙 → top(0) 被完全堵死 → 不合法
      final result = QuoridorEngine.placeWall(state, 0, 0, WallOrientation.vertical);
      expect(result, isNull, reason: 'top 被封死不能放');
    });

    test('放墙后 topWallsPlaced +1', () {
      var state = QuoridorEngine.initialize();
      state = QuoridorEngine.placeWall(state, 3, 4, WallOrientation.horizontal)!;
      expect(state.topWallsPlaced, 1, reason: 'top 放了第一块墙');
    });

    test('wallCountPerPlayer 用尽后再放 → null', () {
      var state = QuoridorEngine.initialize();
      // 模拟 top 已放置 10 面墙
      state = state.copyWith(topWallsPlaced: 10);
      final result = QuoridorEngine.placeWall(state, 3, 4, WallOrientation.horizontal);
      expect(result, isNull, reason: '墙数用尽');
    });

    test('坐标越界 (8,0) horizontal → null（修正 Swift bug）', () {
      final state = QuoridorEngine.initialize();
      final result = QuoridorEngine.placeWall(
        state, 8, 0, WallOrientation.horizontal,
      );
      expect(result, isNull, reason: 'x=8 超出 [0,7] 范围');
    });
  });

  group('胜负', () {
    test('top 走到 y=8 → checkStatus = topWin', () {
      // bottom 不在目标行（y=4），路径长度 > 1 → topWin
      final state = QuoridorEngine.fromBoardSpec(
        topPlayerId: 76, // x=4,y=8 已到达底线
        bottomPlayerId: 40, // x=4,y=4 不在目标行
        currentPlayerIsTop: true,
      );
      final status = QuoridorEngine.checkStatus(
        state.adjacency, 76, 40,
      );
      expect(status, GameStatus.topWin);
    });

    test('bottom 走到 y=0 → checkStatus = bottomWin', () {
      // top 不在目标行（y=4），路径长度 > 1 → bottomWin
      final state = QuoridorEngine.fromBoardSpec(
        topPlayerId: 40, // x=4,y=4 不在目标行
        bottomPlayerId: 4, // x=4,y=0 已到达底线
        currentPlayerIsTop: false,
      );
      final status = QuoridorEngine.checkStatus(
        state.adjacency, 40, 4,
      );
      expect(status, GameStatus.bottomWin);
    });

    test('top 和 bottom 都在底线 → draw', () {
      // Swift checkStatus 逻辑：
      //   if topPlayer.y == 8 {
      //     if GameAi.pathForPlayer(false).count == 1 { return .Draw }
      //     return .TopWin
      //   }
      // path.length==1 意味着起点就是终点（已在目标行）
      // 所以 top.y==8 且 bottom.y==0 → 进入第一支，bottom path=[0] length=1 → Draw
      final state = QuoridorEngine.fromBoardSpec(
        topPlayerId: 72, // x=0,y=8
        bottomPlayerId: 0, // x=0,y=0
        currentPlayerIsTop: true,
      );
      final status = QuoridorEngine.checkStatus(
        state.adjacency, 72, 0,
      );
      expect(status, GameStatus.draw,
          reason: 'top 在 y=8, bottom 在 y=0 → draw');
    });

    test('普通状态 → running', () {
      final state = QuoridorEngine.initialize();
      final status = QuoridorEngine.checkStatus(
        state.adjacency, 4, 76,
      );
      expect(status, GameStatus.running);
    });
  });

  group('applyMoveRecord', () {
    test('走棋 → 移动方 cellId 更新、history +1', () {
      var s = QuoridorEngine.initialize();
      // top 走到 cellId 13（初始 validMoves 含 13）
      s = QuoridorEngine.applyMoveRecord(
        s, MoveRecord.move(cellId: 13, isTopPlayer: true));
      expect(s.topPlayerId, 13, reason: 'top 应移到 13');
      expect(s.bottomPlayerId, 76, reason: 'bottom 不动');
      expect(s.history.length, 1);
      expect(s.history.last.isWall, false);
    });

    test('放墙 → wallGrid 3 格 true、邻接切断、计数 +1', () {
      var s = QuoridorEngine.initialize();
      s = QuoridorEngine.applyMoveRecord(
        s, MoveRecord.wall(x: 3, y: 4, orientation: WallOrientation.horizontal, isTopPlayer: true));
      // wallBaseId(3,4)=160 → horizontal 占 [159,160,161]
      expect(s.wallGrid[159], true);
      expect(s.wallGrid[160], true);
      expect(s.wallGrid[161], true);
      // 邻接切断 (39,48) 与 (40,49)
      expect(s.adjacency[39].contains(48), false);
      expect(s.adjacency[40].contains(49), false);
      expect(s.topWallsPlaced, 1);
      expect(s.bottomWallsPlaced, 0);
      expect(s.history.length, 1);
    });

    test('按 record.isTopPlayer 应用，不看 state.currentPlayerIsTop', () {
      // 故意把 state 的回合设成 bottom，但 record 声明 top
      var s = QuoridorEngine.initialize().copyWith(currentPlayerIsTop: false);
      s = QuoridorEngine.applyMoveRecord(
        s, MoveRecord.move(cellId: 13, isTopPlayer: true));
      expect(s.topPlayerId, 13, reason: 'record 说是 top，就动 top');
      expect(s.currentPlayerIsTop, false, reason: 'applyMoveRecord 不翻回合');
    });
  });

  group('replay', () {
    test('replayHistory([]) == initialize()', () {
      final r = QuoridorEngine.replayHistory(const []);
      final init = QuoridorEngine.initialize();
      expect(r.topPlayerId, init.topPlayerId);
      expect(r.bottomPlayerId, init.bottomPlayerId);
      expect(r.currentPlayerIsTop, true);
      expect(r.status, GameStatus.running);
      expect(r.wallGrid, equals(init.wallGrid));
    });

    test('upTo clamp：<0 → 0，>length → length', () {
      final game = buildMixedGame();
      final n = game.history.length;
      expect(QuoridorEngine.replayHistory(game.history, upTo: -3).topPlayerId,
             QuoridorEngine.replayHistory(game.history, upTo: 0).topPlayerId,
             reason: 'upTo<0 等价 upTo=0');
      expect(QuoridorEngine.replayHistory(game.history, upTo: n + 5).history.length, n,
             reason: 'upTo>length 钳到 length');
    });

    test('replay ≡ live：逐手快照与 replayHistory(upTo:k) 完全一致', () {
      final game = buildMixedGame();
      expect(game.snapshots, isNotEmpty, reason: 'fixture 应产出至少 1 手');
      for (var k = 0; k < game.snapshots.length; k++) {
        final snap = game.snapshots[k];
        final replayed = QuoridorEngine.replayHistory(game.history, upTo: k + 1);
        expect(replayed.topPlayerId, snap.topPlayerId, reason: 'move ${k + 1} topId');
        expect(replayed.bottomPlayerId, snap.bottomPlayerId, reason: 'move ${k + 1} botId');
        expect(replayed.topWallsPlaced, snap.topWallsPlaced, reason: 'move ${k + 1} topWalls');
        expect(replayed.bottomWallsPlaced, snap.bottomWallsPlaced, reason: 'move ${k + 1} botWalls');
        expect(replayed.currentPlayerIsTop, snap.currentPlayerIsTop, reason: 'move ${k + 1} turn');
        expect(replayed.status, snap.status, reason: 'move ${k + 1} status');
        expect(replayed.validMoves, unorderedEquals(snap.validMoves), reason: 'move ${k + 1} validMoves');
        expect(replayed.wallGrid, equals(snap.wallGrid), reason: 'move ${k + 1} wallGrid');
        expect(replayed.history.length, snap.history.length, reason: 'move ${k + 1} history len');
        for (var i = 0; i < 81; i++) {
          expect(replayed.adjacency[i], unorderedEquals(snap.adjacency[i]),
              reason: 'move ${k + 1} adjacency[$i]');
        }
      }
    });

    test('回放后回合：currentPlayerIsTop = !history[k-1].isTopPlayer', () {
      final game = buildMixedGame();
      expect(QuoridorEngine.replayHistory(game.history, upTo: 0).currentPlayerIsTop, true);
      for (var k = 1; k <= game.history.length; k++) {
        final lastTop = game.history[k - 1].isTopPlayer;
        expect(QuoridorEngine.replayHistory(game.history, upTo: k).currentPlayerIsTop,
               !lastTop, reason: 'upTo=$k');
      }
    });

    test('fromJson + 调用方 replayHistory 闭环 → adjacency/wallGrid 复现', () {
      final game = buildMixedGame();
      final finalState = game.snapshots.last;
      final decoded = GameState.fromJson(finalState.toJson());
      expect(decoded.adjacency.every((s) => s.isEmpty), true, reason: 'fromJson 不重建 adjacency');
      final rebuilt = QuoridorEngine.replayHistory(decoded.history);
      expect(rebuilt.topPlayerId, finalState.topPlayerId);
      expect(rebuilt.bottomPlayerId, finalState.bottomPlayerId);
      expect(rebuilt.wallGrid, equals(finalState.wallGrid));
      for (var i = 0; i < 81; i++) {
        expect(rebuilt.adjacency[i], unorderedEquals(finalState.adjacency[i]));
      }
    });
  });
}
