import '../surround_game_constants.dart';

/// 玩家输入模型
///
/// 客机向主机发送的操作指令。
/// 含 stepNumber 用于顺序校验，防止重复处理。
class PlayerInput {
  final String playerId;
  final Direction direction;
  final int stepNumber;

  const PlayerInput({
    required this.playerId,
    required this.direction,
    required this.stepNumber,
  });

  Map<String, dynamic> toJson() => {
    'playerId': playerId,
    'direction': direction.name,
    'stepNumber': stepNumber,
  };

  factory PlayerInput.fromJson(Map<String, dynamic> json) {
    return PlayerInput(
      playerId: json['playerId'] as String,
      direction: Direction.values.firstWhere(
        (e) => e.name == json['direction'],
        orElse: () => Direction.up,
      ),
      stepNumber: json['stepNumber'] as int? ?? 0,
    );
  }
}
