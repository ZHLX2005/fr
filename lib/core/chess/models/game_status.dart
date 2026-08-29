// lib/core/chess/models/game_status.dart
//
// 游戏终局状态判定：playing / check / checkmate / stalemate / 其他和棋

import 'piece.dart';

/// 游戏状态
enum GameStatus {
  /// 还在下（合法走法非空）
  playing,

  /// 当前方被将军（仍有合法走法）
  check,

  /// 当前方被将杀（无合法走法 + 被将军）
  checkmate,

  /// 僵局：当前方无合法走法且未被将军
  stalemate,

  /// 50 回合规则（双方都没有吃子 + 兵未动 ≥ 50 半回合）
  fiftyMoveRule,

  /// 三次重复局面（same position 三次 → 可宣告和棋）
  threefold,

  /// 死局（无可救药的死局例如一方只剩 1 兵 vs 对方 1 车 → 协议和棋）
  deadPosition,

  /// 投降
  resign,

  /// 协议和棋
  agreedDraw,

  /// 时间超时
  timeout,
}

/// 状态描述信息 —— UI 用
extension GameStatusInfo on GameStatus {
  /// 是不是终局（game over）
  bool get isGameOver => index >= GameStatus.checkmate.index;

  /// 是不是"和棋"类终局
  bool get isDraw => index >= GameStatus.stalemate.index &&
      index <= GameStatus.agreedDraw.index;

  /// 谁赢了？
  ///
  /// 返回 null = 和棋
  /// 返回 PlayerColor = 赢的一方（将军方的对侧 = 输）
  PieceColor? winner(GameStatus status, PieceColor sideToMove) {
    if (status == GameStatus.checkmate) {
      // 被将杀方输
      return opposite(sideToMove);
    }
    if (status == GameStatus.resign ||
        status == GameStatus.timeout) {
      // 调用方需独立记录投降方；本方法假设"当前方投降"
      return opposite(sideToMove);
    }
    return null;
  }

  String label(String lang) {
    // 极简中文标签（i18n 由 ui 层接管）；UI 应该用 localization 包
    switch (this) {
      case GameStatus.playing:
        return lang == 'zh' ? '对弈中' : 'Playing';
      case GameStatus.check:
        return lang == 'zh' ? '将军' : 'Check';
      case GameStatus.checkmate:
        return lang == 'zh' ? '将杀' : 'Checkmate';
      case GameStatus.stalemate:
        return lang == 'zh' ? '僵局' : 'Stalemate';
      case GameStatus.fiftyMoveRule:
        return lang == 'zh' ? '50 回合规则和棋' : '50-move rule';
      case GameStatus.threefold:
        return lang == 'zh' ? '三次重复和棋' : 'Threefold repetition';
      case GameStatus.deadPosition:
        return lang == 'zh' ? '死局和棋' : 'Dead position';
      case GameStatus.resign:
        return lang == 'zh' ? '认输' : 'Resignation';
      case GameStatus.agreedDraw:
        return lang == 'zh' ? '协议和棋' : 'Draw by agreement';
      case GameStatus.timeout:
        return lang == 'zh' ? '超时' : 'Time forfeit';
    }
  }
}
