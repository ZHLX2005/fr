// lib/core/jungle_chess/lan/serializer/game_state_serializer.dart
import 'package:flutter/foundation.dart';
import '../../models/game_state.dart';

class GameStateSerializer {
  Map<String, dynamic> serialize(ValueNotifier<GameState> notifier) {
    return notifier.value.toJson();
  }

  ValueNotifier<GameState> deserialize(Map<String, dynamic> data, ValueNotifier<GameState> target) {
    final rebuilt = GameState.fromJson(data);
    target.value = rebuilt;
    return target;
  }
}
