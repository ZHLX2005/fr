import '../models/game_room.dart';
import '../models/game_state.dart';
import '../surround_game_constants.dart';

// ===== Host events =====
sealed class LanHostEvent {
  const LanHostEvent();
}

class HostCreateRoomPressed extends LanHostEvent {
  const HostCreateRoomPressed();
}

/// 主机携带已经存在的房间对象进入等待页（来自 LanLobbyPage 的初始房间）
class HostCreateRoomWithRoom extends LanHostEvent {
  const HostCreateRoomWithRoom(this.room);
  final GameRoom room;
}

class HostStartGamePressed extends LanHostEvent {
  const HostStartGamePressed();
}

class HostClientJoined extends LanHostEvent {
  const HostClientJoined(this.clientId, this.clientName);

  final String clientId;
  final String clientName;
}

class HostClientLeft extends LanHostEvent {
  const HostClientLeft();
}

class HostMoveReceived extends LanHostEvent {
  const HostMoveReceived(this.moveData);

  final (
    int targetCellId,
    int? wallX,
    int? wallY,
    WallOrientation? wallOrientation,
  ) moveData;
}

class HostMoveCommitted extends LanHostEvent {
  const HostMoveCommitted(this.moveData);

  final (
    int targetCellId,
    int? wallX,
    int? wallY,
    WallOrientation? wallOrientation,
  ) moveData;
}

class HostTick extends LanHostEvent {
  const HostTick();
}

class HostAbortGame extends LanHostEvent {
  const HostAbortGame();
}

class HostRetryPressed extends LanHostEvent {
  const HostRetryPressed();
}

class HostExitRequested extends LanHostEvent {
  const HostExitRequested();
}

// ===== Client events =====
sealed class LanClientEvent {
  const LanClientEvent();
}

class ClientJoinPressed extends LanClientEvent {
  const ClientJoinPressed(this.room);

  final GameRoom room;
}

class ClientJoinAccepted extends LanClientEvent {
  const ClientJoinAccepted(this.room);

  final GameRoom room;
}

class ClientJoinRejected extends LanClientEvent {
  const ClientJoinRejected(this.reason);

  final String reason;
}

class HostStartedCountdown extends LanClientEvent {
  const HostStartedCountdown(this.secondsLeft);

  final int secondsLeft;
}

class ClientTick extends LanClientEvent {
  const ClientTick();
}

class ClientMoveCommitted extends LanClientEvent {
  const ClientMoveCommitted(this.moveData);

  final (
    int targetCellId,
    int? wallX,
    int? wallY,
    WallOrientation? wallOrientation,
  ) moveData;
}

class HostStatePushed extends LanClientEvent {
  const HostStatePushed(this.gameState);

  final GameState gameState;
}

class ClientReconnectPressed extends LanClientEvent {
  const ClientReconnectPressed();
}

class ClientExitRequested extends LanClientEvent {
  const ClientExitRequested();
}
