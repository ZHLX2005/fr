// Reversi (Othello) 黑白翻转棋 - 游戏状态
//
// 配合 [ReversiNotifier]（ChangeNotifier）使用，遵循项目 word_drag 模块的
// 手写 ChangeNotifier 状态管理范式（provider + context.watch 消费）。
//
// 历史栈 [history] 记录每一次"落子前"的完整快照，用于悔棋。
// 悔棋策略：回到当前方上一次面临决策的状态（自动跳过 pass 的视觉回合）。

import '../models/reversi_board.dart';

/// 游戏进行状态
enum ReversiStatus { playing, blackWon, whiteWon, draw }

/// 历史快照：记录某次落子前的完整状态，供悔棋回溯
class ReversiSnapshot {
  final ReversiBoard board;
  final PieceType currentPlayer;
  final Position? lastMove;

  const ReversiSnapshot({
    required this.board,
    required this.currentPlayer,
    this.lastMove,
  });
}

/// 翻转棋状态
class ReversiState {
  /// 当前棋盘
  final ReversiBoard board;

  /// 当前应落子方
  final PieceType currentPlayer;

  /// 游戏状态
  final ReversiStatus status;

  /// 历史快照栈（最近一次在末尾）
  final List<ReversiSnapshot> history;

  /// 最近一步落子位置（用于高亮）
  final Position? lastMove;

  /// 状态提示（仅在 pass / 结束 / 悔棋等特殊事件设置，正常回合为 null）
  final String? message;

  const ReversiState({
    required this.board,
    required this.currentPlayer,
    required this.status,
    required this.history,
    this.lastMove,
    this.message,
  });

  /// 初始状态：标准开局，黑方先行
  factory ReversiState.initial() {
    return ReversiState(
      board: ReversiBoard.initial(),
      currentPlayer: PieceType.black,
      status: ReversiStatus.playing,
      history: const [],
      lastMove: null,
      message: null,
    );
  }

  /// 黑方棋子数
  int get blackScore => board.count(PieceType.black);

  /// 白方棋子数
  int get whiteScore => board.count(PieceType.white);

  /// 已落子总数
  int get totalStones => blackScore + whiteScore;

  /// 当前方是否有合法步可下
  bool get hasLegalMove => board.legalMovesFor(currentPlayer).isNotEmpty;

  /// 当前方的合法落子位置
  List<Position> get legalMoves => board.legalMovesFor(currentPlayer);

  /// 当前方是否可悔棋
  ///
  /// 对手曾在历史中落子即可悔（undo 时搜索对手的快照）。
  /// 若对手从未落子则无可悔。
  bool get canUndo {
    final opponent = currentPlayer.opponent;
    for (var i = history.length - 1; i >= 0; i--) {
      if (history[i].currentPlayer == opponent) return true;
    }
    return false;
  }

  /// 游戏是否结束
  bool get isOver => status != ReversiStatus.playing;

  /// 不可变 copyWith
  ReversiState copyWith({
    ReversiBoard? board,
    PieceType? currentPlayer,
    ReversiStatus? status,
    List<ReversiSnapshot>? history,
    Position? lastMove,
    String? message,
    bool clearMessage = false,
  }) {
    return ReversiState(
      board: board ?? this.board,
      currentPlayer: currentPlayer ?? this.currentPlayer,
      status: status ?? this.status,
      history: history ?? this.history,
      // lastMove / message 允许显式置 null，故直接赋值
      lastMove: lastMove,
      message: clearMessage ? null : (message ?? this.message),
    );
  }
}
