// test/core/chess/castling_perft_test.dart
//
// Perft (Performance Test) —— 国际象棋走法生成的数学级验证。
//
// 原理：从标准局面穷举所有合法走法序列到指定深度，比对节点总数。
// 数值来自 Chess Programming Wiki（业界公认基准）。王车易位的任何差错
// （多生成 / 少生成 / 应用错误 / 权利撤销错误）都会立刻导致计数不符 ——
// 这是比手写用例强得多的"全规则等价"证明。
//
// 覆盖标准位置：
//   · Initial     —— 标准开局
//   · Kiwipete    —— 双方 KQkq 全易位权 + 攻击线交错（易位试金石）
//   · Position 3  —— 吃过路兵 / 边界攻击
//   · Position 4  —— 升变 + 易位权交错
//   · Position 5  —— 易位 + 升变混合
//
// 白棋易位专项（本任务背景）：Kiwipete 中白方 O-O / O-O-O 各出现在
// 大量节点路径上，若白棋易位生成/应用有误，d3 计数必然偏离 97862。

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/chess/chess.dart';

const ChessEngine engine = ChessEngine();

/// Perft：以 [s] 为根、深度 [depth] 的合法走法树叶子计数。
///
/// depth <= 0 返回 1（空路径本身算一个叶子）——这是 divide(d1) 等
/// 场景下 perft(child, 0) 的合法调用，缺了它会无限递归爆栈。
/// depth == 1 直接返回合法走法数（不再递归 applyMove）——
/// 与逐层递归计数等价，但省掉每叶子一次 applyMove。
int perft(BoardState s, int depth) {
  if (depth <= 0) return 1;
  final moves = engine.generateLegalMoves(s);
  if (depth == 1) return moves.length;
  var nodes = 0;
  for (final m in moves) {
    nodes += perft(applyMove(s, m).nextState, depth - 1);
  }
  return nodes;
}

/// （诊断用）divide：按根走法分组输出 perft(depth-1)，
/// 失败时打印可逐项比对 CPW divide 表定位差异。
Map<String, int> divide(BoardState s, int depth) {
  final out = <String, int>{};
  for (final m in engine.generateLegalMoves(s)) {
    out[m.toUci()] = perft(applyMove(s, m).nextState, depth - 1);
  }
  return out;
}

void perftCheck(String name, String fen, int depth, int expected) {
  final s = FenCodec.fromFen(fen);
  final got = perft(s, depth);
  // divide 只在计数不符时才计算（惰性求值）——Dart 的 reason: 参数
  // 是急切求值的，放进去会在断言通过时也跑一遍 divide 浪费时间。
  if (got != expected) {
    fail('$name perft($depth) 计数不符（fen=$fen）\n'
        'got=$got expected=$expected\n'
        'divide：${divide(s, depth)}');
  }
}

void main() {
  group('Perft —— 标准位置（CPW 基准值）', () {
    test('Initial：d3 = 8902', () {
      perftCheck(
        'Initial',
        'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        3,
        8902,
      );
    });

    test('Kiwipete（双方便利位）：d1 = 48, d2 = 2039, d3 = 97862', () {
      // 白方易位专项：Kiwipete 中白 O-O / O-O-O 均合法且出现在海量路径上。
      perftCheck(
        'Kiwipete',
        'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
        1,
        48,
      );
      perftCheck(
        'Kiwipete',
        'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
        2,
        2039,
      );
      perftCheck(
        'Kiwipete',
        'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
        3,
        97862,
      );
    });

    test('Position 3（吃过路兵边界）：d3 = 2812, d4 = 43238', () {
      perftCheck(
        'Position 3',
        '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1',
        3,
        2812,
      );
      perftCheck(
        'Position 3',
        '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1',
        4,
        43238,
      );
    });

    test('Position 4（升变+易位权交错）：d2 = 264, d3 = 9467', () {
      perftCheck(
        'Position 4',
        'r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1',
        2,
        264,
      );
      perftCheck(
        'Position 4',
        'r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1',
        3,
        9467,
      );
    });

    test('Position 5（易位+升变混合）：d2 = 1486, d3 = 62379', () {
      perftCheck(
        'Position 5',
        'rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8',
        2,
        1486,
      );
      perftCheck(
        'Position 5',
        'rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8',
        3,
        62379,
      );
    });
  });
}
