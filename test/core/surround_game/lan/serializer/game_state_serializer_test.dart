// test/core/surround_game/lan/serializer/game_state_serializer_test.dart
//
// TDD: GameState 序列化器 round-trip
//   - 序列化 → 反序列化后状态等价（特别是 history 长度、玩家 ID、
//     currentPlayerIsTop、status、adjacency 数量 81）
//   - 反序列化后 target 触发一次 Listenable 通知
//   - 反序列化失败（缺字段）抛异常但 target.value 不被污染

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/surround_game/engine/game_engine.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/serializer/game_state_serializer.dart';
import 'package:xiaodouzi_fr/core/surround_game/models/game_state.dart';

void main() {
  group('GameStateSerializer', () {
    test('serialize/deserialize 重建后历史一致', () {
      // 构造一个有 3 步历史的状态
      final s0 = QuoridorEngine.initialize();
      final s1 = QuoridorEngine.movePiece(s0, 13)!; // top 走
      final s2 = QuoridorEngine.switchTurn(s1);
      final s3 = QuoridorEngine.movePiece(s2, 67)!; // bottom 走
      final src = QuoridorEngine.switchTurn(s3);

      final notifier = ValueNotifier<GameState>(src);
      addTearDown(notifier.dispose);

      const serializer = GameStateSerializer();
      final json = serializer.serialize(notifier);

      // 制造一个"全新" target，反序列化后应与原状态等价
      final target = ValueNotifier<GameState>(QuoridorEngine.initialize());
      addTearDown(target.dispose);
      var listenerCount = 0;
      target.addListener(() => listenerCount++);

      serializer.deserialize(json, target);

      expect(target.value.history.length, src.history.length);
      expect(target.value.topPlayerId, src.topPlayerId);
      expect(target.value.bottomPlayerId, src.bottomPlayerId);
      expect(target.value.currentPlayerIsTop, src.currentPlayerIsTop);
      expect(target.value.status, src.status);
      expect(target.value.adjacency.length, 81, reason: '邻接表应有 81 个格子');
      expect(listenerCount, 1, reason: 'target.value 赋值应触发 Listenable 通知');
    });

    test('deserialize 失败的 JSON 抛但不污染 target', () {
      const serializer = GameStateSerializer();
      final target = ValueNotifier<GameState>(QuoridorEngine.initialize());
      addTearDown(target.dispose);
      final before = target.value;

      expect(
        () => serializer.deserialize(
          {'__invalid__': true}, // GameState.fromJson 会因缺字段抛
          target,
        ),
        throwsA(anything),
      );
      // target.value 未被污染（deserialize 失败前/后值不变）
      expect(identical(target.value, before), isTrue);
    });
  });
}
