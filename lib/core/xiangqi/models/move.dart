// lib/core/xiangqi/models/move.dart
//
// 一手棋 —— 中国象棋走法用「起点记号 + 终点记号」两段表示（如 "b0e2"）。
//
// 与国际象棋 UCI（"e2e4"）同构：记号名是 "<列字母 a-i><行号 0-9>"，
// 内部 1D 索引 = row * 9 + col（row 0 在顶部）。
//
// 与 draughts 的 PDN（"32-28"）差异：
//   · 跳棋用方格号（1..50），象棋用「列字母 + 行号」，可读性更好且无需蛇形换算。
//   · 象棋无多跳链 → 一手 = 一个 from/to 对（跳棋的 path 概念不需要）。

import '../constants/xiangqi_constants.dart';
import 'piece.dart';

/// 一手棋。
class XiangqiMove {
  /// 起点 1D 索引
  final int from;

  /// 终点 1D 索引
  final int to;

  /// 被吃掉的棋子（null = 未吃子）
  final XiangqiPiece? captured;

  const XiangqiMove({
    required this.from,
    required this.to,
    this.captured,
  });

  /// 走法记号串（协议层载荷）：如 "b0e2"
  String toUci() => '${xiangqiSquareName(from)}${xiangqiSquareName(to)}';

  /// 解析走法记号串；非法返回 null
  static XiangqiMove? fromUci(String uci) {
    if (uci.length != 4) return null;
    final from = xiangqiIndexFromName(uci.substring(0, 2));
    final to = xiangqiIndexFromName(uci.substring(2, 4));
    if (from < 0 || to < 0) return null;
    return XiangqiMove(from: from, to: to);
  }

  /// 起点记号名
  String get fromName => xiangqiSquareName(from);

  /// 终点记号名
  String get toName => xiangqiSquareName(to);

  bool get isCapture => captured != null;

  @override
  bool operator ==(Object other) =>
      other is XiangqiMove && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => toUci();
}
