// test/go_lua_engine_test.dart
// 联机围棋 — 客户端规则复刻单测（与 Lua 同一算法）
//
// 覆盖：提子 / 提群 / 自杀 / 打劫(simple ko) / 数子 / atari
// 棋盘坐标 board[y][x]：0=空 1=黑 2=白
// 算法参考 orca0613/go-game test.py（3×3 用例，映射到 9×9）
//
// ⚠️ 坐标语义：`applyMove(board, x, y, color)` 与 `libertiesAt(board, x, y)` 的
//    x = 列（col）、y = 行（row），与棋盘二维索引 board[y][x] 对应。
//    落子前该点必须为空（占位返回 null）。
//
// ⚠️ 9×9 与 orca 3×3 的差异：orca 3×3 用例的"围圈"棋形只在整盘即棋盘边缘时封闭；
//    映射到 9×9 时，若圈沿不在棋盘边缘，环外空点会漏气（= 气），不构成围困。
//    因此提子/自杀用例均用「环 + 外围墙封口」的合法构造，保证被提群/自杀点
//    在落子前恰好 1 气（或无气）。
//
// ⚠️ detectArea 是客户端终局数子：把"接棋盘边界的开阔空区"也计入围空
//   （与标准围棋"无边权"不同，但跨端一致即可——服务端只比对双方对同一色点数的判定，
//   不校验规则正确性）。

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/go_lua/go_engine.dart';

void main() {
  GoBoard empty() => List.generate(
      kGoSize, (_) => List<int>.filled(kGoSize, 0));

  void setBoard(GoBoard b, List<(int, int, int)> stones) {
    for (final (y, x, v) in stones) { b[y][x] = v; }
  }

  group('提子 capture', () {
    test('落子提掉无气单子（orca test_capturing_move 语义）', () {
      final b = empty();
      // 白单子 (1,1) 三面被黑围：(0,1)(1,0)(2,1) 黑，唯一气 = (1,2) 空。
      // 黑落 (row=1,col=2) → 白(1,1) 无气被提。
      setBoard(b, [
        (0, 1, 1),
        (1, 0, 1), (1, 1, 2),
        (2, 1, 1),
      ]);
      // 前态合法性：白(1,1) 有 1 气 (1,2)
      expect(GoRoom.libertiesAt(b, 1, 1).length, 1);
      expect(GoRoom.libertiesAt(b, 1, 1), contains((1, 2)));
      final after = GoRoom.applyMove(b, 2, 1, 1);  // 黑落 (x=2, y=1)
      expect(after, isNotNull);
      expect(after![1][1], 0);  // 白(1,1) 被提
      expect(after[1][2], 1);   // 黑(1,2) 已落
      expect(after[0][1], 1);   // 邻居黑(0,1) 保留
      expect(after[2][1], 1);   // 下方黑(2,1) 保留
    });

    test('落子提掉整个无气群（orca test_capturing_move_huge 语义）', () {
      final b = empty();
      // 白环 (6..8)² 中心 (7,7) 空 = 白环唯一气；环外圈黑墙封死，白环无外气。
      // 黑落 (7,7) → 白环 8 子无气被提。
      setBoard(b, [
        // 外围黑墙（封住白环外气）
        (5, 5, 1), (5, 6, 1), (5, 7, 1), (5, 8, 1),
        (6, 5, 1), (7, 5, 1), (8, 5, 1),
        // 白环
        (6, 6, 2), (6, 7, 2), (6, 8, 2),
        (7, 6, 2),            (7, 8, 2),
        (8, 6, 2), (8, 7, 2), (8, 8, 2),
      ]);
      // 前态合法性：白环唯一气 = 中心 (7,7)
      expect(GoRoom.libertiesAt(b, 6, 6).length, 1);
      expect(GoRoom.libertiesAt(b, 6, 6), contains((7, 7)));
      final after = GoRoom.applyMove(b, 7, 7, 1);  // 黑落中心
      expect(after, isNotNull);
      expect(after![7][7], 1);  // 黑中心保留
      // 白环 8 子全被提 → 除中心黑外全空
      for (final (y, x) in [(6,6),(6,7),(6,8),(7,6),(7,8),(8,6),(8,7),(8,8)]) {
        expect(after[y][x], 0, reason: '白($y,$x) 应被提');
      }
    });

    test('提二连白子：黑落点填最后气提整群', () {
      final b = empty();
      // 白二连 (6,7)(6,8) 贴右上角。row5 黑墙 + (6,6) 黑 + (7,8)(8,8) 黑。
      // 白群唯一气 = (7,7)。黑落 (7,7) → 白二子无气被提。
      setBoard(b, [
        (6, 7, 2), (6, 8, 2),          // 白二连
        (5, 6, 1), (5, 7, 1), (5, 8, 1),  // 上黑墙
        (6, 6, 1),                       // 左黑
        (7, 8, 1), (8, 8, 1),            // 右下黑
      ]);
      expect(GoRoom.libertiesAt(b, 7, 6).length, 1);
      expect(GoRoom.libertiesAt(b, 7, 6), contains((7, 7)));
      final after = GoRoom.applyMove(b, 7, 7, 1);  // 黑落唯一气 → 提白二子
      expect(after, isNotNull);
      expect(after![6][7], 0);
      expect(after[6][8], 0);
      expect(after[7][7], 1);
    });
  });

  group('自杀 suicide', () {
    test('完全包围的空点落己方子为自杀（orca test_suicide_move_huge 语义）', () {
      final b = empty();
      // 黑环 (0..2)² 中心 (1,1) 空；环外一圈白墙封死 → 中心无气。
      // 黑落 (1,1)：killed 空（无对方群）+ 自身黑群无气 → 自杀。
      setBoard(b, [
        // 黑环
        (0, 0, 1), (0, 1, 1), (0, 2, 1),
        (1, 0, 1),            (1, 2, 1),
        (2, 0, 1), (2, 1, 1), (2, 2, 1),
        // 环外白墙（封住黑环外气）
        (0, 3, 2), (1, 3, 2), (2, 3, 2),
        (3, 0, 2), (3, 1, 2), (3, 2, 2),
      ]);
      final after = GoRoom.applyMove(b, 1, 1, 1);
      expect(after, isNull);  // 自杀 → 非法
    });

    test('提子优先于自杀：落子提掉对方群时即便自身无气也不判自杀', () {
      final b = empty();
      // 白环 (6..8)² 中心 (7,7) 空 = 白环唯一气；环外黑墙封死。
      // 黑落 (7,7)：killed 非空（白环）→ 提白环，非自杀。
      setBoard(b, [
        (5, 5, 1), (5, 6, 1), (5, 7, 1), (5, 8, 1),
        (6, 5, 1), (7, 5, 1), (8, 5, 1),
        (6, 6, 2), (6, 7, 2), (6, 8, 2),
        (7, 6, 2),            (7, 8, 2),
        (8, 6, 2), (8, 7, 2), (8, 8, 2),
      ]);
      final after = GoRoom.applyMove(b, 7, 7, 1);
      expect(after, isNotNull);  // 提白环，非自杀
      expect(after![7][7], 1);
      expect(after[6][6], 0);
      expect(after[8][8], 0);
    });
  });

  group('打劫 simple ko', () {
    test('simple ko 形状：落子后单提单子（orca test_ko 语义）', () {
      final b = empty();
      // orca test_ko 3×3：
      // [".", "b", "w"]
      // ["b", "w", "."]
      // [".", ".", "w"]
      // 9×9 上白(0,2) 的右邻 (0,3) 是空点 → 白(0,2) 有 2 气 (0,3)(1,2)，
      // 不构成 orca 的"1 气"前态。补一颗黑到 (0,3)，让白(0,2) 唯一气 = (1,2)。
      // 黑落 (row=1,col=2) → 单提白(0,2)（simple ko 的"提"）。
      setBoard(b, [
        (0, 1, 1), (0, 2, 2), (0, 3, 1),
        (1, 0, 1), (1, 1, 2),
        (2, 2, 2),
      ]);
      // 前态合法性：白(0,2) 恰好 1 气 (1,2)
      expect(GoRoom.libertiesAt(b, 2, 0).length, 1);
      expect(GoRoom.libertiesAt(b, 2, 0), contains((1, 2)));
      final after = GoRoom.applyMove(b, 2, 1, 1);  // 黑落 (x=2, y=1)
      expect(after, isNotNull);
      expect(after![0][2], 0);  // 白(0,2) 被提
      expect(after[1][2], 1);   // 黑(1,2) 已落
      // 劫禁由服务端 on_action_MOVE 权威执行（ko_spot 比对），客户端 applyMove 不消费 ko。
      // 服务端 ko 校验已由 Task 2 的 gopher-lua 测试覆盖。此用例验证「提子」行为正确。
    });
  });

  group('数子 detectArea', () {
    test('空盘全空 → 0/0', () {
      final b = empty();
      final area = GoRoom.detectArea(b);
      expect(area.black, 0);
      expect(area.white, 0);
    });

    test('单黑子角落 → 黑81（当前实现：开阔空区全计黑）', () {
      final b = empty();
      b[0][0] = 1;
      final area = GoRoom.detectArea(b);
      expect(area.black, 81);  // 子 1 + 开阔空区 80（全连通到角上黑子）
      expect(area.white, 0);
    });

    test('黑白围成的空区归属', () {
      final b = empty();
      // 黑围左上角一块空（角部封闭，空点(1,1) 只邻接黑 → 归黑）。
      // 环外开阔区也与黑环邻接 → 全计黑（当前实现无边权）。
      setBoard(b, [
        (0, 0, 1), (0, 1, 1), (0, 2, 1),
        (1, 0, 1),            (1, 2, 1),
        (2, 0, 1), (2, 1, 1), (2, 2, 1),
      ]);
      final area = GoRoom.detectArea(b);
      expect(area.black, 81);  // 8 黑子 + 中心空(1,1) + 环外开阔区 72，全计黑
      expect(area.white, 0);
    });

    test('开阔空区邻双方 → 无主，不计任何一方', () {
      final b = empty();
      b[0][0] = 1;
      b[4][4] = 2;
      final area = GoRoom.detectArea(b);
      // 除 (0,0) 与 (4,4) 外 79 空点连通一片，同时邻接黑(0,0) 与白(4,4) → 无主。
      // 黑 = 1（子），白 = 1（子）。
      expect(area.black, 1);
      expect(area.white, 1);
    });
  });

  group('atari 打吃', () {
    test('单子只有1气 → isAtari true', () {
      final b = empty();
      b[4][4] = 1;
      b[4][3] = 2; b[4][5] = 2; b[3][4] = 2;  // 三面白
      // (4,4) 黑剩 1 气 (5,4)
      expect(GoRoom.isAtari(b, 4, 4), isTrue);
    });

    test('单子2气 → isAtari false', () {
      final b = empty();
      b[4][4] = 1;
      expect(GoRoom.isAtari(b, 4, 4), isFalse);
    });

    test('整群打吃：黑三子链只有1气 → 群内任一点 isAtari true 且 groupsInAtari 命中整群', () {
      final b = empty();
      // 黑竖链 (4,4)(5,4)(6,4)；四周白封，留 (7,4) 空 = 唯一气。
      b[4][4] = 1; b[5][4] = 1; b[6][4] = 1;
      b[3][4] = 2;
      b[4][3] = 2; b[4][5] = 2;
      b[5][3] = 2; b[5][5] = 2;
      b[6][3] = 2; b[6][5] = 2;
      expect(GoRoom.libertiesAt(b, 4, 4), contains((7, 4)));
      expect(GoRoom.isAtari(b, 4, 4), isTrue);
      expect(GoRoom.isAtari(b, 4, 5), isTrue);  // 链中部 (5,4)
      expect(GoRoom.isAtari(b, 4, 6), isTrue);  // 链尾部 (6,4)
      final inAtari = GoRoom.groupsInAtari(b, 1);
      expect(inAtari, contains((4, 4)));
      expect(inAtari, contains((5, 4)));
      expect(inAtari, contains((6, 4)));
      expect(inAtari, isNot(contains((3, 4))));  // 白子不在打吃
    });

    test('整群非打吃：黑三子链有2气 → isAtari false', () {
      final b = empty();
      b[4][4] = 1; b[5][4] = 1; b[6][4] = 1;
      // 只封两侧，留 (3,4) 与 (7,4) 两个气
      b[4][3] = 2; b[4][5] = 2;
      b[5][3] = 2; b[5][5] = 2;
      b[6][3] = 2; b[6][5] = 2;
      expect(GoRoom.libertiesAt(b, 4, 4).length, 2);
      expect(GoRoom.isAtari(b, 4, 4), isFalse);
      expect(GoRoom.groupsInAtari(b, 1), isEmpty);
    });
  });
}
