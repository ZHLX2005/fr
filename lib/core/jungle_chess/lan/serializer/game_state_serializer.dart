// lib/core/jungle_chess/lan/serializer/game_state_serializer.dart
//
// GameState ↔ Map 序列化器 — 满足 Session 契约。
//
// 反序列化使用 GameState.fromJson 重建完整状态。
// 与 surround_game 不同：JungleChess 的 GameState 自带完整 pieces map，
// 不需要 replayHistory（每步 history 推给对端，对端 GameState 已是终态）。

import 'package:flutter/foundation.dart';
import 'package:xiaodouzi_fr/core/localnet/session/state_serializer.dart';
import '../../models/game_state.dart';

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
    target.value = temp;
    return target;
  }
}