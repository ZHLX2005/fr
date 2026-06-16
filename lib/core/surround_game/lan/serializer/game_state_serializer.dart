// lib/core/surround_game/lan/serializer/game_state_serializer.dart
//
// GameState ↔ Map 序列化器 — 满足 Session 契约。
// 反序列化用 QuoridorEngine.replayHistory 重建 adjacency/wallGrid/validMoves。
//
// target = ValueNotifier<GameState>，in-place 修改 target.value 并返回。

import 'package:flutter/foundation.dart';
import 'package:xiaodouzi_fr/core/localnet/session/state_serializer.dart';
import 'package:xiaodouzi_fr/core/surround_game/engine/game_engine.dart';
import 'package:xiaodouzi_fr/core/surround_game/models/game_state.dart';

class GameStateSerializer
    implements StateSerializer<ValueNotifier<GameState>> {
  const GameStateSerializer();

  @override
  Map<String, dynamic> serialize(ValueNotifier<GameState> notifier) {
    return notifier.value.toJson();
  }

  @override
  ValueNotifier<GameState> deserialize(
    Map<String, dynamic> data,
    ValueNotifier<GameState> target,
  ) {
    final temp = GameState.fromJson(data);
    final rebuilt = QuoridorEngine.replayHistory(temp.history);
    target.value = rebuilt;
    return target;
  }
}
