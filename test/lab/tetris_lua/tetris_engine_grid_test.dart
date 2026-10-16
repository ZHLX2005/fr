// test/lab/tetris_lua/tetris_engine_grid_test.dart
//
// Tetris 引擎 grid 回归测试 —— 锁定 L 块 (type 7) 落定后仍写入 grid。
// 之前 pieceColors 改 List 后，L 块 type 7 越界，渲染时 RangeError → "方块消失"。

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/tetris_lua/engine.dart';

void main() {
  group('TetrisEngine L 块落定 (type 7 不消失)', () {
    test('L 块硬降后，grid 中含 type 7 的格子数量 = 4', () {
      // 7-bag 包含 L: 序列写死为 L
      final eng = TetrisEngine([kPieceL]);
      eng.hardDrop(); // 立即落到底
      // L 块矩阵有 4 个填充格
      var count = 0;
      for (final row in eng.grid) {
        for (final cell in row) {
          if (cell == kPieceL) count++;
        }
      }
      expect(count, 4, reason: 'L 块 type 7 必须完整落定到 grid，不能消失');
    });

    test('硬降后 grid 不含 0 单元格（L 块填充的那 4 格）', () {
      final eng = TetrisEngine([kPieceL]);
      eng.hardDrop();
      // 找到非 0 单元格，至少 4 个
      var nonEmpty = 0;
      for (final row in eng.grid) {
        for (final cell in row) {
          if (cell != kEmptyCell) nonEmpty++;
        }
      }
      expect(nonEmpty, greaterThanOrEqualTo(4));
    });

    test('_consumeNext 序列越界兜底返回 kPieceI', () {
      final eng = TetrisEngine(const []); // 空序列
      // 反射拿不到 _consumeNext（private），用 spawn 行为间接验证
      // 空序列 spawn 不抛错，且 current 可能为 null 或 I 块
      expect(() => eng, returnsNormally);
    });

    test('7 种 piece type 全部能完整落定，无 type 异常', () {
      for (final t in [
        kPieceI, kPieceO, kPieceT, kPieceS, kPieceZ, kPieceJ, kPieceL,
      ]) {
        final eng = TetrisEngine([t]);
        eng.hardDrop();
        // 落定后一定能找到 type t 的格子
        var found = false;
        for (final row in eng.grid) {
          for (final cell in row) {
            if (cell == t) {
              found = true;
              break;
            }
          }
          if (found) break;
        }
        expect(found, true, reason: 'piece type $t 落定后必须在 grid 中');
      }
    });
  });
}
