import '../local/local_match_state.dart';
import 'game_room.dart';
import '../models/game_state.dart';

// ===== Host states =====
sealed class LanHostState {
  const LanHostState();
}

class HostLobby extends LanHostState {
  const HostLobby();
}

class HostWaiting extends LanHostState {
  const HostWaiting(this.room);

  final GameRoom room;
}

class HostCountdown extends LanHostState {
  const HostCountdown(this.room, this.secondsLeft);

  final GameRoom room;
  final int secondsLeft;
}

class HostInGame extends LanHostState {
  const HostInGame(this.gameState, this.room);

  final GameState gameState;
  final GameRoom room;
}

class HostFinished extends LanHostState {
  const HostFinished(this.finalState, this.room, this.result);

  final GameState finalState;
  final GameRoom room;
  final GameResult result;
}

class HostError extends LanHostState {
  const HostError(this.message, {this.previous});

  final String message;
  final LanHostState? previous;
}

// ===== Client states =====
sealed class LanClientState {
  const LanClientState();
}

class ClientIdle extends LanClientState {
  const ClientIdle();
}

class ClientJoining extends LanClientState {
  const ClientJoining(this.targetRoom);

  final GameRoom targetRoom;
}

class ClientWaiting extends LanClientState {
  const ClientWaiting(this.room);

  final GameRoom room;
}

class ClientCountdown extends LanClientState {
  const ClientCountdown(this.room, this.secondsLeft);

  final GameRoom room;
  final int secondsLeft;
}

class ClientInGame extends LanClientState {
  const ClientInGame(this.gameState, this.room);

  final GameState gameState;
  final GameRoom room;
}

class ClientFinished extends LanClientState {
  const ClientFinished(this.finalState, this.room, this.result);

  final GameState finalState;
  final GameRoom room;
  final GameResult result;
}

class ClientDisconnected extends LanClientState {
  const ClientDisconnected({this.canReconnect = true});

  final bool canReconnect;
}
