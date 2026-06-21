// lib/core/jungle_chess/lan/lan_match_state.dart
import '../models/game_state.dart';
import 'game_room.dart';

// === Host 状态 ===
sealed class LanHostState {
  const LanHostState();
}

final class HostLobby extends LanHostState {
  const HostLobby();
}

final class HostWaiting extends LanHostState {
  final GameRoom room;
  const HostWaiting({required this.room});
}

final class HostCountdown extends LanHostState {
  final GameRoom room;
  final int secondsLeft;
  const HostCountdown({required this.room, required this.secondsLeft});
}

final class HostInGame extends LanHostState {
  final GameState gameState;
  const HostInGame({required this.gameState});
}

final class HostFinished extends LanHostState {
  final GameState gameState;
  const HostFinished({required this.gameState});
}

final class HostError extends LanHostState {
  final String message;
  final LanHostState? previous;
  const HostError(this.message, {this.previous});
}

// === Client 状态 ===
sealed class LanClientState {
  const LanClientState();
}

final class ClientIdle extends LanClientState {
  const ClientIdle();
}

final class ClientJoining extends LanClientState {
  final GameRoom targetRoom;
  const ClientJoining({required this.targetRoom});
}

final class ClientWaiting extends LanClientState {
  final GameRoom room;
  const ClientWaiting({required this.room});
}

final class ClientCountdown extends LanClientState {
  final GameRoom room;
  final int secondsLeft;
  const ClientCountdown({required this.room, required this.secondsLeft});
}

final class ClientInGame extends LanClientState {
  final GameState gameState;
  const ClientInGame({required this.gameState});
}

final class ClientFinished extends LanClientState {
  final GameState gameState;
  const ClientFinished({required this.gameState});
}

final class ClientDisconnected extends LanClientState {
  final String message;
  const ClientDisconnected({this.message = ''});
}
