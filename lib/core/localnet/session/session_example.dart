import 'package:flutter/foundation.dart';
import 'package:xiaodouzi_fr/core/localnet/framework/lan_framework.dart';
import 'package:xiaodouzi_fr/core/localnet/framework/framework_config.dart';
import 'package:xiaodouzi_fr/core/localnet/session/state_serializer.dart';

/// Example: Chess game with automatic state synchronization
///
/// Before (manual sync):
/// ```dart
/// game.move('e2', 'e4');
/// framework.sendTo(B_id, 'chess', game.toJson());
///
/// framework.watchChannel('chess').listen((msg) {
///   game.applyMove(msg.payload['from'], msg.payload['to']);
///   renderBoard();
/// });
/// ```
///
/// After (automatic sync):
/// ```dart
/// final session = framework.createSession(
///   peerId: B_id,
///   state: ChessGame(),
/// );
///
/// session.onChanged = () => renderBoard(session.state.board);
/// game.move('e2', 'e4');  // Auto-syncs!
/// ```

class ChessGame extends ChangeNotifier {
  ChessGame();

  final List<String> _moves = [];

  List<String> get moves => List.unmodifiable(_moves);

  void move(String from, String to) {
    _moves.add('$from-$to');
    notifyListeners();
  }

  /// Apply move from remote (used by deserializer)
  void _applyMove(String moveNotation) {
    _moves.add(moveNotation);
  }

  ChessGame copyWith({List<String>? moves}) {
    final game = ChessGame();
    game._moves.addAll(moves ?? _moves);
    return game;
  }
}

/// Chess game state serializer
class ChessGameSerializer implements StateSerializer<ChessGame> {
  @override
  Map<String, dynamic> serialize(ChessGame state) {
    return {'moves': state.moves};
  }

  @override
  ChessGame deserialize(Map<String, dynamic> data, ChessGame target) {
    target._moves.clear();
    final movesList = data['moves'] as List;
    for (final move in movesList) {
      target._applyMove(move as String);
    }
    return target;
  }
}

/// Usage example
Future<void> chessGameExample() async {
  final framework = LanFramework.instance;
  await framework.start(const FrameworkConfig(deviceAlias: 'Player A'));

  final game = ChessGame();
  final session = framework.createSession(
    peerId: 'player-b-device-id',
    state: game,
    serializer: ChessGameSerializer(),
  );

  // UI refresh callback
  session.onChanged = () {
    print('Board updated: ${game.moves}');
  };

  // Make a move - automatically synced to opponent
  game.move('e2', 'e4');

  // Cleanup
  await session.dispose();
  await framework.stop();
}
