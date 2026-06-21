// lib/core/jungle_chess/models/game_state.dart
import 'piece.dart';
import 'move.dart';

/// 不可变游戏状态
final class GameState {
  /// key: 1D index 0-62
  final Map<int, Piece> pieces;
  final PlayerColor currentTurn;
  final List<Move> history;
  final PlayerColor? winner;
  final String? gameOverReason;

  const GameState({
    required this.pieces, required this.currentTurn,
    this.history = const [], this.winner, this.gameOverReason,
  });

  bool get isOver => winner != null;
  int get roundCount => history.length;

  GameState copyWith({
    Map<int, Piece>? pieces, PlayerColor? currentTurn,
    List<Move>? history, PlayerColor? winner, String? gameOverReason,
  }) => GameState(
    pieces: pieces ?? this.pieces,
    currentTurn: currentTurn ?? this.currentTurn,
    history: history ?? this.history,
    winner: winner ?? this.winner,
    gameOverReason: gameOverReason ?? this.gameOverReason,
  );

  Map<String, dynamic> toJson() => {
    'pieces': pieces.map((k, v) => MapEntry(k.toString(), v.toJson())),
    'currentTurn': currentTurn.index,
    'history': history.map((m) => m.toJson()).toList(),
    'winner': winner?.index, 'gameOverReason': gameOverReason,
  };

  factory GameState.fromJson(Map<String, dynamic> j) {
    return GameState(
      pieces: (j['pieces'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(int.parse(k), Piece.fromJson(v as Map<String, dynamic>))),
      currentTurn: PlayerColor.values[j['currentTurn'] as int],
      history: (j['history'] as List).map((m) => Move.fromJson(m as Map<String, dynamic>)).toList(),
      winner: j['winner'] != null ? PlayerColor.values[j['winner'] as int] : null,
      gameOverReason: j['gameOverReason'] as String?,
    );
  }
}
