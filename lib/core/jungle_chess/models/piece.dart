// lib/core/jungle_chess/models/piece.dart
import '../constants/jungle_constants.dart';

/// 坐标
typedef Coord = ({int row, int col});

extension CoordUtils on Coord {
  int get index => row * kBoardCols + col;
  bool get isValid => row >= 0 && row < kBoardRows && col >= 0 && col < kBoardCols;
  bool get isRiverCell => isRiver(index);
  static Coord fromIndex(int i) => (row: i ~/ kBoardCols, col: i % kBoardCols);
}

/// 动物等级
enum Animal {
  rat(1), cat(2), dog(3), wolf(4),
  leopard(5), tiger(6), lion(7), elephant(8);
  const Animal(this.rank);
  final int rank;
}

/// 玩家颜色
enum PlayerColor { blue, red }

/// 棋子
final class Piece {
  final Animal animal;
  final PlayerColor color;
  final Coord position;
  final bool isAlive;

  const Piece({
    required this.animal, required this.color,
    required this.position, this.isAlive = true,
  });

  Piece copyWith({Animal? animal, PlayerColor? color, Coord? position, bool? isAlive}) {
    return Piece(
      animal: animal ?? this.animal,
      color: color ?? this.color,
      position: position ?? this.position,
      isAlive: isAlive ?? this.isAlive,
    );
  }

  String get assetPath {
    return 'assets/animals/${kAnimalFile[animal]!}';
  }

  Map<String, dynamic> toJson() => {
    'animal': animal.index, 'color': color.index,
    'row': position.row, 'col': position.col, 'isAlive': isAlive,
  };

  factory Piece.fromJson(Map<String, dynamic> j) => Piece(
    animal: Animal.values[j['animal'] as int],
    color: PlayerColor.values[j['color'] as int],
    position: (row: j['row'] as int, col: j['col'] as int),
    isAlive: j['isAlive'] as bool? ?? true,
  );

  @override
  bool operator ==(Object other) =>
    other is Piece && animal == other.animal && color == other.color &&
    position.row == other.position.row && position.col == other.position.col &&
    isAlive == other.isAlive;

  @override
  int get hashCode => Object.hash(animal, color, position.row, position.col, isAlive);
}
