// lib/core/xiangqi/jieqi/jieqi_state.dart
//
// 揭棋（暗棋变体玩法）状态。
//
// ## 揭棋规则要点（本期实现的口径）
//
//   · 开局：将 / 帅**明置**原位（col 4 底线）；其余每方 15 子
//     （车马炮士象各 2 + 卒/兵 5）洗乱后暗置己方 15 个起始点
//     （洗牌在服务端 Lua，见 p2p/script/xiangqi_script_lifecycle.dart
//     的 jieqi_shuffled_fen）。
//   · 暗子按**所在点位的棋种走法**走出第一步（兵位暗子第一步只能向前
//     一格、车位暗子第一步按车走……），走完自动翻开为明子。
//   · 翻开后的士可以出九宫 / 过河（斜行一格全盘），象可以过河
//     （仍走田、保留塞象眼）—— 其余棋种翻开后走法与中国象棋一致。
//   · 将军 / 绝杀 / 困毙规则与中国象棋相同（将帅始终明置，不存在暗将）。
//
// ## 信息表示
//
//   · 棋盘永远是「真实棋盘」（XiangqiBoardState，每格是真实棋种）——
//     FEN 上的字面就是真实棋种（见 xiangqi_room_page 的信任模型说明）。
//   · 「哪些子还是暗子」由 [hidden] 集合表达（1D 索引）。
//     客户端从「初始暗置集合 − 已移动过的子」推得（[jieqiReplayStates]），
//     不需要共享随机种子。
//
// ## 与标准象棋引擎的关系
//
//   走法生成 / 将军判定复用 engine/move_generator.dart，方式是
//   **虚拟棋盘**（[jieqiVirtualBoard]）：把暗子按其点位棋种替换后，
//   交给标准走法生成器 —— 暗子「按所在位置照中国象棋规则走出第一步」
//   正是「真实棋种 → 点位棋种」的替换。翻开的士象放宽走法单独生成
//   （标准生成器会把士锁在九宫、象锁在半场）。

import '../constants/xiangqi_constants.dart';
import '../models/board_state.dart';
import '../models/piece.dart';

/// 揭棋对局状态：真实棋盘 + 暗子集合（不可变值，更新走 [jieqiApplyMove]）。
class JieqiState {
  /// 真实棋盘（每格是真实棋种；暗子的真实棋种也在这里，但 UI 渲染时
  /// 对 [hidden] 里的格只画背面圆盘）。
  final XiangqiBoardState board;

  /// 仍是暗子的格子（1D 索引集合）。
  final Set<int> hidden;

  const JieqiState({required this.board, required this.hidden});

  /// 某格棋子是否为暗子
  bool isHidden(int index) => hidden.contains(index);

  @override
  bool operator ==(Object other) =>
      other is JieqiState &&
      other.board == board &&
      _setEquals(other.hidden, hidden);

  @override
  int get hashCode => Object.hash(board, Object.hashAllUnordered(hidden));

  static bool _setEquals(Set<int> a, Set<int> b) =>
      a.length == b.length && a.every(b.contains);
}

/// 揭棋开局暗置集合：除双将（帅/将）外全部暗置。
///
/// 前提是 [board] 来自揭棋开局 FEN（服务端 jieqi_shuffled_fen 产物）：
/// 双将明置原位、其余 30 子暗置。标准开局 FEN 传入时会把非将子全部
/// 当暗子 —— 调用方必须先判 variant == 'jieqi'。
Set<int> jieqiInitialHidden(XiangqiBoardState board) {
  final out = <int>{};
  for (final (idx, piece) in board.occupied) {
    if (piece.isGeneral) continue; // 将/帅明置
    out.add(idx);
  }
  return out;
}

/// 点位棋种：揭棋开局里该起始点「名义上的棋种」。
///
/// 暗子第一步按它所在**点位**的棋种走法走（不是按真实棋种）：
///   · 底线（row 0 / row 9）：col 0/8 车位、1/7 马位、2/6 象位、
///     3/5 士位、4 将位（将帅明置，暗子不会落在这里）；
///   · row 2 / row 7：炮位（col 1 / col 7）；
///   · row 3 / row 6：兵/卒位（col 0/2/4/6/8）。
///
/// 非起始点返回 pawn 兜底 —— 暗子只会在起始点上（走一步即翻开），
/// 该分支仅用于防御畸形局面。
XiangqiPieceType jieqiRoleTypeAt(int index) {
  final row = xiangqiRowOf(index);
  final col = xiangqiColOf(index);
  if (row == 0 || row == 9) {
    switch (col) {
      case 0:
      case 8:
        return XiangqiPieceType.chariot;
      case 1:
      case 7:
        return XiangqiPieceType.horse;
      case 2:
      case 6:
        return XiangqiPieceType.elephant;
      case 3:
      case 5:
        return XiangqiPieceType.advisor;
      default:
        return XiangqiPieceType.general;
    }
  }
  if (row == 2 || row == 7) {
    if (col == 1 || col == 7) return XiangqiPieceType.cannon;
  }
  if (row == 3 || row == 6) {
    if (col == 0 || col == 2 || col == 4 || col == 6 || col == 8) {
      return XiangqiPieceType.pawn;
    }
  }
  // 非起始点：防御兜底（暗子不会停在非起始点 —— 走一步就翻开）
  return XiangqiPieceType.pawn;
}
