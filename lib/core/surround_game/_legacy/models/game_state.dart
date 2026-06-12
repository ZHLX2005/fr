import 'dart:math';
import '../../surround_game_constants.dart';

/// 游戏状态模型
///
/// 围追堵截的棋盘、玩家位置、分数等全部状态。
/// 不可变对象，每次操作返回新实例。
class GameState {
  final List<List<CellState>> board;
  final Point<int> hostPos;
  final Point<int> clientPos;
  final int hostScore;
  final int clientScore;
  final int stepNumber;
  final bool isGameOver;
  final String? winnerId;

  const GameState({
    required this.board,
    required this.hostPos,
    required this.clientPos,
    required this.hostScore,
    required this.clientScore,
    required this.stepNumber,
    this.isGameOver = false,
    this.winnerId,
  });

  /// 初始化棋盘
  factory GameState.initialize() {
    final board = List.generate(
      SurroundGameConstants.boardRows,
      (_) => List.filled(SurroundGameConstants.boardCols, CellState.empty),
    );

    // 设置边界
    for (int c = 0; c < SurroundGameConstants.boardCols; c++) {
      board[0][c] = CellState.wall;
      board[SurroundGameConstants.boardRows - 1][c] = CellState.wall;
    }
    for (int r = 0; r < SurroundGameConstants.boardRows; r++) {
      board[r][0] = CellState.wall;
      board[r][SurroundGameConstants.boardCols - 1] = CellState.wall;
    }

    return GameState(
      board: board,
      hostPos: Point<int>(
        SurroundGameConstants.hostStartRow,
        SurroundGameConstants.hostStartCol,
      ),
      clientPos: Point<int>(
        SurroundGameConstants.clientStartRow,
        SurroundGameConstants.clientStartCol,
      ),
      hostScore: 0,
      clientScore: 0,
      stepNumber: 0,
    );
  }

  /// 快捷访问格子
  CellState getCell(int row, int col) {
    if (row < 0 || row >= board.length) return CellState.wall;
    if (col < 0 || col >= board[0].length) return CellState.wall;
    return board[row][col];
  }

  GameState copyWith({
    List<List<CellState>>? board,
    Point<int>? hostPos,
    Point<int>? clientPos,
    int? hostScore,
    int? clientScore,
    int? stepNumber,
    bool? isGameOver,
    String? winnerId,
  }) {
    return GameState(
      board: board ?? this.board,
      hostPos: hostPos ?? this.hostPos,
      clientPos: clientPos ?? this.clientPos,
      hostScore: hostScore ?? this.hostScore,
      clientScore: clientScore ?? this.clientScore,
      stepNumber: stepNumber ?? this.stepNumber,
      isGameOver: isGameOver ?? this.isGameOver,
      winnerId: winnerId ?? this.winnerId,
    );
  }

  Map<String, dynamic> toJson() => {
    'board': board.map((row) => row.map((c) => c.name).toList()).toList(),
    'hostRow': hostPos.x,
    'hostCol': hostPos.y,
    'clientRow': clientPos.x,
    'clientCol': clientPos.y,
    'hostScore': hostScore,
    'clientScore': clientScore,
    'stepNumber': stepNumber,
    'isGameOver': isGameOver,
    'winnerId': winnerId,
  };

  factory GameState.fromJson(Map<String, dynamic> json) {
    final board = (json['board'] as List)
        .map((row) => (row as List)
            .map((c) => CellState.values.firstWhere(
                  (e) => e.name == c,
                  orElse: () => CellState.empty,
                ))
            .toList())
        .toList();

    return GameState(
      board: board,
      hostPos: Point<int>(json['hostRow'] as int, json['hostCol'] as int),
      clientPos: Point<int>(json['clientRow'] as int, json['clientCol'] as int),
      hostScore: json['hostScore'] as int,
      clientScore: json['clientScore'] as int,
      stepNumber: json['stepNumber'] as int,
      isGameOver: json['isGameOver'] as bool? ?? false,
      winnerId: json['winnerId'] as String?,
    );
  }
}
