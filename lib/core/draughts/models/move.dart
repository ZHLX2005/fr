// lib/core/draughts/models/move.dart
//
// 走法（不可变 value）。
// 与国际象棋 Move 的关键差异：
//   · 跳棋的"吃子"是一整条链（多跳），不是单步 → 需要 path + capturedSquares。
//   · 无升变选择（升王由规则强制，不是玩家选）→ 只有 isPromotion 标记。
//   · 无特殊标记（无易位/无吃过路兵）。

import '../constants/draughts_constants.dart';

/// 不可变走法。
///
/// 普通走法：path = [from, to]，capturedSquares 为空。
/// 吃子（含多跳）：path = [from, s1, s2, ..., to]，capturedSquares = 各被吃子所在格。
class DraughtsMove {
  /// 起始格 1D 索引
  final int from;

  /// 终止格 1D 索引（= path.last）
  final int to;

  /// 途经格（含 from 与 to）；普通走法长度 2
  final List<int> path;

  /// 被吃子所在的格子（按捕获顺序）；整手结束时才从棋盘移除
  final List<int> capturedSquares;

  /// 走完是否升王（仅当是兵且停在对方底线）
  final bool isPromotion;

  const DraughtsMove({
    required this.from,
    required this.to,
    required this.path,
    this.capturedSquares = const [],
    this.isPromotion = false,
  });

  /// 便利构造：普通一步
  factory DraughtsMove.simple(int from, int to, {bool isPromotion = false}) =>
      DraughtsMove(
        from: from,
        to: to,
        path: [from, to],
        isPromotion: isPromotion,
      );

  /// 是否吃子走法
  bool get isCapture => capturedSquares.isNotEmpty;

  /// 吃子数
  int get captureCount => capturedSquares.length;

  /// PDN 记号：走子 `32-28`，吃子 `32x23`（多跳 `32x23x14`）。
  ///
  /// 跳棋 PDN 用方格号（1..50）书写；本方法把内部索引换算成方格号。
  String toPdn() {
    final buf = StringBuffer();
    final sep = isCapture ? 'x' : '-';
    for (var i = 0; i < path.length; i++) {
      if (i > 0) buf.write(sep);
      buf.write(draughtsSquareNumberOfIndex(path[i]));
    }
    return buf.toString();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DraughtsMove) return false;
    if (from != other.from || to != other.to) return false;
    if (isPromotion != other.isPromotion) return false;
    if (path.length != other.path.length) return false;
    if (capturedSquares.length != other.capturedSquares.length) return false;
    for (var i = 0; i < path.length; i++) {
      if (path[i] != other.path[i]) return false;
    }
    for (var i = 0; i < capturedSquares.length; i++) {
      if (capturedSquares[i] != other.capturedSquares[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    var h = Object.hash(from, to, isPromotion);
    for (final p in path) {
      h = Object.hash(h, p);
    }
    for (final c in capturedSquares) {
      h = Object.hash(h, c);
    }
    return h;
  }

  @override
  String toString() => toPdn();
}
