import 'package:flutter_test/flutter_test.dart';

import 'package:xiaodouzi_fr/core/surround_game/engine/game_engine.dart';
import 'package:xiaodouzi_fr/core/surround_game/models/game_state.dart';
import 'package:xiaodouzi_fr/core/surround_game/surround_game_constants.dart';

void main() {
  group('GameState', () {
    test('构造含默认字段 → 字段值正确', () {
      final state = GameState(
        adjacency: List.generate(81, (_) => <int>{}),
        wallGrid: List.filled(289, false),
        topPlayerId: 4,
        bottomPlayerId: 76,
        currentPlayerIsTop: true,
        topWallsPlaced: 0,
        bottomWallsPlaced: 0,
        history: const [],
        status: GameStatus.running,
        validMoves: {13, 3, 5},
      );

      expect(state.topPlayerId, 4);
      expect(state.bottomPlayerId, 76);
      expect(state.currentPlayerIsTop, true);
      expect(state.status, GameStatus.running);
      expect(state.validMoves, containsAll([13, 3, 5]));
      expect(state.adjacency.length, 81);
      expect(state.wallGrid.length, 289);
    });

    test('copyWith 只修改单字段', () {
      final state = GameState(
        adjacency: List.generate(81, (_) => <int>{}),
        wallGrid: List.filled(289, false),
        topPlayerId: 4,
        bottomPlayerId: 76,
        currentPlayerIsTop: true,
        topWallsPlaced: 0,
        bottomWallsPlaced: 0,
        history: const [],
        status: GameStatus.running,
        validMoves: {13, 3, 5},
      );

      final modified = state.copyWith(topPlayerId: 13);
      expect(modified.topPlayerId, 13, reason: 'topPlayerId 应更新');
      expect(state.bottomPlayerId, 76, reason: '原对象 bottom 不变');
      expect(state.currentPlayerIsTop, true, reason: '原对象不变');
    });

    test('toJson → fromJson 往返一致', () {
      final state = GameState(
        adjacency: List.generate(81, (_) => <int>{}),
        wallGrid: List.filled(289, false),
        topPlayerId: 4,
        bottomPlayerId: 76,
        currentPlayerIsTop: true,
        topWallsPlaced: 0,
        bottomWallsPlaced: 0,
        history: [
          MoveRecord.move(cellId: 13, isTopPlayer: true),
        ],
        status: GameStatus.running,
        validMoves: {13, 3, 5},
      );

      final json = state.toJson();
      final decoded = GameState.fromJson(json);

      expect(decoded.topPlayerId, state.topPlayerId);
      expect(decoded.bottomPlayerId, state.bottomPlayerId);
      expect(decoded.currentPlayerIsTop, state.currentPlayerIsTop);
      expect(decoded.status, state.status);
      expect(decoded.history.length, 1);
      expect(decoded.history[0].isWall, false);
    });

    test('fromBoardSpec 构造测试局面 → adjacency 与 wallGrid 一致', () {
      final state = QuoridorEngine.fromBoardSpec(
        topPlayerId: 4,
        bottomPlayerId: 76,
        currentPlayerIsTop: true,
        placedWalls: [
          (x: 3, y: 4, o: WallOrientation.horizontal),
        ],
      );
      expect(state.topPlayerId, 4);
      expect(state.bottomPlayerId, 76);
      expect(state.adjacency.length, 81);
      expect(state.wallGrid.length, 289);
      // 横墙 (3,4) 占用了 3 个 wallGrid 单元
      // wallBaseId(3,4) = (3*2+1)+(4*2+1)*17 = 7+9*17 = 7+153 = 160
      // horizontal → [159, 160, 161]
      expect(state.wallGrid[159], true, reason: '横墙左');
      expect(state.wallGrid[160], true, reason: '横墙中');
      expect(state.wallGrid[161], true, reason: '横墙右');
      // 横墙切断 (baseId, baseId+9) 和 (baseId+1, baseId+10)
      // baseId = x + y*9 = 3+4*9 = 39
      // 切断 (39,48) 和 (40,49)
      expect(state.adjacency[39].contains(48), false);
      expect(state.adjacency[40].contains(49), false);
    });
  });

  group('MoveRecord', () {
    test('move 工厂设置正确字段', () {
      final record = MoveRecord.move(cellId: 13, isTopPlayer: true);
      expect(record.x, 4, reason: 'cellId=13 → x=13%9=4');
      expect(record.y, 1, reason: 'cellId=13 → y=13~/9=1');
      expect(record.isWall, false);
      expect(record.isTopPlayer, true);
      expect(record.orientation, isNull);
    });

    test('wall 工厂设置正确字段', () {
      final record = MoveRecord.wall(
        x: 3,
        y: 4,
        orientation: WallOrientation.horizontal,
        isTopPlayer: false,
      );
      expect(record.x, 3);
      expect(record.y, 4);
      expect(record.isWall, true);
      expect(record.isTopPlayer, false);
      expect(record.orientation, WallOrientation.horizontal);
    });

    test('MoveRecord toJson → fromJson 往返', () {
      final original = MoveRecord.wall(
        x: 2,
        y: 5,
        orientation: WallOrientation.vertical,
        isTopPlayer: true,
      );
      final json = original.toJson();
      final decoded = MoveRecord.fromJson(json);
      expect(decoded.x, original.x);
      expect(decoded.y, original.y);
      expect(decoded.isWall, original.isWall);
      expect(decoded.orientation, original.orientation);
      expect(decoded.isTopPlayer, original.isTopPlayer);
    });
  });
}
