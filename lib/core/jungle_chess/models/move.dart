// lib/core/jungle_chess/models/move.dart
import 'piece.dart';

/// 走法记录（不可变）
final class Move {
  final Coord from;
  final Coord to;
  final Animal animal;
  final bool isRiverJump;
  final Piece? captured;
  final int roundNumber;

  const Move({
    required this.from, required this.to, required this.animal,
    this.isRiverJump = false, this.captured,
    required this.roundNumber,
  });

  Map<String, dynamic> toJson() => {
    'fromRow': from.row, 'fromCol': from.col,
    'toRow': to.row, 'toCol': to.col,
    'animal': animal.index, 'isRiverJump': isRiverJump,
    'captured': captured?.toJson(), 'roundNumber': roundNumber,
  };

  Move copyWith({
    Coord? from,
    Coord? to,
    Animal? animal,
    bool? isRiverJump,
    Piece? captured,
    int? roundNumber,
  }) {
    return Move(
      from: from ?? this.from,
      to: to ?? this.to,
      animal: animal ?? this.animal,
      isRiverJump: isRiverJump ?? this.isRiverJump,
      captured: captured ?? this.captured,
      roundNumber: roundNumber ?? this.roundNumber,
    );
  }

  @override
  bool operator ==(Object other) =>
    other is Move &&
    from.row == other.from.row && from.col == other.from.col &&
    to.row == other.to.row && to.col == other.to.col &&
    animal == other.animal &&
    isRiverJump == other.isRiverJump &&
    captured == other.captured &&
    roundNumber == other.roundNumber;

  @override
  int get hashCode => Object.hash(
    from.row, from.col,
    to.row, to.col,
    animal,
    isRiverJump,
    captured,
    roundNumber,
  );

  factory Move.fromJson(Map<String, dynamic> j) => Move(
    from: (row: j['fromRow'] as int, col: j['fromCol'] as int),
    to: (row: j['toRow'] as int, col: j['toCol'] as int),
    animal: Animal.values[j['animal'] as int],
    isRiverJump: j['isRiverJump'] as bool? ?? false,
    captured: j['captured'] != null
      ? Piece.fromJson(j['captured'] as Map<String, dynamic>) : null,
    roundNumber: j['roundNumber'] as int,
  );
}
