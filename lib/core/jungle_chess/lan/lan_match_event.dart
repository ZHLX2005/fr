// lib/core/jungle_chess/lan/lan_match_event.dart
import '../models/piece.dart';
import 'game_room.dart';

// === Host 事件 ===
sealed class LanHostEvent {
  const LanHostEvent();
}

final class HostCreateRoom extends LanHostEvent {
  final String roomId;
  final String hostName;
  const HostCreateRoom({required this.roomId, required this.hostName});
}

final class HostStartGame extends LanHostEvent {
  const HostStartGame();
}

final class HostMoveCommitted extends LanHostEvent {
  final Coord from;
  final Coord to;
  const HostMoveCommitted({required this.from, required this.to});
}

final class HostCountdownTick extends LanHostEvent {
  final int secondsLeft;
  const HostCountdownTick({required this.secondsLeft});
}

final class HostExit extends LanHostEvent {
  const HostExit();
}

// === Client 事件 ===
sealed class LanClientEvent {
  const LanClientEvent();
}

final class ClientJoinRoom extends LanClientEvent {
  final GameRoom room;
  const ClientJoinRoom({required this.room});
}

final class ClientExit extends LanClientEvent {
  const ClientExit();
}
