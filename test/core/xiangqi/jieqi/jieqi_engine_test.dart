// test/core/xiangqi/jieqi/jieqi_engine_test.dart
//
// 揭棋引擎测试 —— 暗子点位走法 / 翻开变脸 / 士象放宽 / 将军判定 / 重放。
//
// 造局约定：用 cells 直接摆**最小验证局面**（将军 / 放宽走法的单元验证
// 不需要合法开局；暗子必然摆在起始点上 —— 走一步即翻开）。

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/xiangqi/constants/xiangqi_constants.dart';
import 'package:xiaodouzi_fr/core/xiangqi/engine/fen_codec.dart';
import 'package:xiaodouzi_fr/core/xiangqi/engine/move_generator.dart';
import 'package:xiaodouzi_fr/core/xiangqi/jieqi/jieqi_engine.dart';
import 'package:xiaodouzi_fr/core/xiangqi/jieqi/jieqi_state.dart';
import 'package:xiaodouzi_fr/core/xiangqi/models/board_state.dart';
import 'package:xiaodouzi_fr/core/xiangqi/models/game_status.dart';
import 'package:xiaodouzi_fr/core/xiangqi/models/move.dart';
import 'package:xiaodouzi_fr/core/xiangqi/models/piece.dart';

/// 最小揭棋风格局面：双将原位 + col4 屏障黑卒（防「将帅照面」把
/// 一切走法判非法）+ 指定格子摆子（可覆盖屏障位）。
XiangqiBoardState _board(Map<int, XiangqiPiece> pieces,
    {XiangqiColor side = XiangqiColor.red}) {
  final cells = List<int?>.filled(kXiangqiCells, null);
  cells[xiangqiIndex(0, 4)] = XiangqiPiece.blackGeneral.pack();
  cells[xiangqiIndex(9, 4)] = XiangqiPiece.redGeneral.pack();
  cells[xiangqiIndex(4, 4)] = XiangqiPiece.blackPawn.pack();
  for (final e in pieces.entries) {
    cells[e.key] = e.value.pack();
  }
  return XiangqiBoardState(cells: cells, sideToMove: side);
}

JieqiState _state(
  Map<int, XiangqiPiece> pieces, {
  required Set<int> hidden,
  XiangqiColor side = XiangqiColor.red,
}) =>
    JieqiState(board: _board(pieces, side: side), hidden: hidden);

Set<int> _targetsOf(List<XiangqiMove> moves, int from) =>
    moves.where((m) => m.from == from).map((m) => m.to).toSet();

const _kXiangqiLikeFen =
    'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 0 1';

void main() {
  group('点位棋种映射（jieqiRoleTypeAt）', () {
    test('底线：车马象士 + 将位', () {
      expect(jieqiRoleTypeAt(xiangqiIndex(9, 0)), XiangqiPieceType.chariot);
      expect(jieqiRoleTypeAt(xiangqiIndex(9, 8)), XiangqiPieceType.chariot);
      expect(jieqiRoleTypeAt(xiangqiIndex(9, 1)), XiangqiPieceType.horse);
      expect(jieqiRoleTypeAt(xiangqiIndex(9, 7)), XiangqiPieceType.horse);
      expect(jieqiRoleTypeAt(xiangqiIndex(9, 2)), XiangqiPieceType.elephant);
      expect(jieqiRoleTypeAt(xiangqiIndex(9, 6)), XiangqiPieceType.elephant);
      expect(jieqiRoleTypeAt(xiangqiIndex(9, 3)), XiangqiPieceType.advisor);
      expect(jieqiRoleTypeAt(xiangqiIndex(9, 5)), XiangqiPieceType.advisor);
      expect(jieqiRoleTypeAt(xiangqiIndex(9, 4)), XiangqiPieceType.general);
      expect(jieqiRoleTypeAt(xiangqiIndex(0, 0)), XiangqiPieceType.chariot);
      expect(jieqiRoleTypeAt(xiangqiIndex(0, 3)), XiangqiPieceType.advisor);
    });

    test('炮位 / 兵卒位 / 非起始点兜底', () {
      expect(jieqiRoleTypeAt(xiangqiIndex(7, 1)), XiangqiPieceType.cannon);
      expect(jieqiRoleTypeAt(xiangqiIndex(7, 7)), XiangqiPieceType.cannon);
      expect(jieqiRoleTypeAt(xiangqiIndex(2, 1)), XiangqiPieceType.cannon);
      expect(jieqiRoleTypeAt(xiangqiIndex(2, 7)), XiangqiPieceType.cannon);
      expect(jieqiRoleTypeAt(xiangqiIndex(6, 0)), XiangqiPieceType.pawn);
      expect(jieqiRoleTypeAt(xiangqiIndex(6, 8)), XiangqiPieceType.pawn);
      expect(jieqiRoleTypeAt(xiangqiIndex(3, 4)), XiangqiPieceType.pawn);
      expect(jieqiRoleTypeAt(xiangqiIndex(5, 3)), XiangqiPieceType.pawn,
          reason: '非起始点 → pawn 兜底（防御分支）');
    });
  });

  group('初始暗置集合', () {
    test('揭棋开局：除双将外全部暗置（30 枚）', () {
      final hidden =
          jieqiInitialHidden(boardStateFromFen(_kXiangqiLikeFen));
      expect(hidden.length, 30);
      expect(hidden.contains(xiangqiIndex(9, 4)), isFalse, reason: '红帅明置');
      expect(hidden.contains(xiangqiIndex(0, 4)), isFalse, reason: '黑将明置');
      expect(hidden.contains(xiangqiIndex(9, 0)), isTrue);
      expect(hidden.contains(xiangqiIndex(6, 4)), isTrue);
    });
  });

  group('虚拟棋盘（暗子按点位棋种替换）', () {
    test('暗马在车位 → 虚拟棋盘上是车；明子原样', () {
      final horseAtChariotPoint =
          XiangqiPiece(XiangqiColor.red, XiangqiPieceType.horse);
      final revealedPawn = XiangqiPiece(XiangqiColor.red, XiangqiPieceType.pawn);
      final state = _state(
        {
          xiangqiIndex(9, 0): horseAtChariotPoint,
          xiangqiIndex(9, 2): revealedPawn,
        },
        hidden: {xiangqiIndex(9, 0)},
      );
      final v = jieqiVirtualBoard(state);
      expect(v.pieceAt(xiangqiIndex(9, 0))!.type, XiangqiPieceType.chariot,
          reason: '暗子按点位棋种（车位 → 车）');
      expect(v.pieceAt(xiangqiIndex(9, 2))!.type, XiangqiPieceType.pawn,
          reason: '明子不受虚拟化影响');
      expect(v.pieceAt(xiangqiIndex(9, 4))!.type, XiangqiPieceType.general);
    });
  });

  group('暗子走法（按点位棋种）', () {
    test('兵位暗子第一步只能向前一格', () {
      final hiddenHorse = XiangqiPiece(XiangqiColor.red, XiangqiPieceType.horse);
      final state = _state(
        {xiangqiIndex(6, 0): hiddenHorse},
        hidden: {xiangqiIndex(6, 0)},
      );
      expect(
        _targetsOf(jieqiLegalMoves(state), xiangqiIndex(6, 0)),
        {xiangqiIndex(5, 0)},
        reason: '兵位暗子按兵走：只进不横（未过河）—— 真实棋种（马）不参与',
      );
    });

    test('车位暗子按车走（直线滑行）', () {
      final hiddenHorse = XiangqiPiece(XiangqiColor.red, XiangqiPieceType.horse);
      final state = _state(
        {xiangqiIndex(9, 0): hiddenHorse},
        hidden: {xiangqiIndex(9, 0)},
      );
      final targets = _targetsOf(
        jieqiLegalMoves(state),
        xiangqiIndex(9, 0),
      );
      expect(targets, contains(xiangqiIndex(9, 1)), reason: '车式横滑');
      expect(targets, contains(xiangqiIndex(8, 0)), reason: '车式纵滑');
      expect(targets, isNot(contains(xiangqiIndex(7, 1))),
          reason: '真实棋种（马走日）不得出现');
    });

    test('暗子走完自动翻开（真实棋种落位、暗子集合收缩）', () {
      final hiddenHorse = XiangqiPiece(XiangqiColor.red, XiangqiPieceType.horse);
      final state = _state(
        {xiangqiIndex(9, 0): hiddenHorse},
        hidden: {xiangqiIndex(9, 0)},
      );
      final next = jieqiApplyMove(
        state,
        XiangqiMove(from: xiangqiIndex(9, 0), to: xiangqiIndex(8, 0)),
      );
      expect(next.board.pieceAt(xiangqiIndex(8, 0))!.type,
          XiangqiPieceType.horse, reason: '翻开后按真实棋种');
      expect(next.hidden, isEmpty);
    });

    test('吃掉暗子 → 该子离场（hidden 收缩）', () {
      final redRook = XiangqiPiece(XiangqiColor.red, XiangqiPieceType.chariot);
      final blackHiddenPawn =
          XiangqiPiece(XiangqiColor.black, XiangqiPieceType.pawn);
      final from = xiangqiIndex(6, 0);
      final to = xiangqiIndex(3, 0);
      final state = _state(
        {from: redRook, to: blackHiddenPawn},
        hidden: {to},
      );
      final next = jieqiApplyMove(
        state,
        XiangqiMove(from: from, to: to, captured: blackHiddenPawn),
      );
      // 吃子 = 吃子方落位终点、被吃暗子从盘上消失（且其暗子身份一并清除）
      final landed = next.board.pieceAt(to);
      expect(landed, isNotNull);
      expect(landed!.color, XiangqiColor.red);
      expect(landed.type, XiangqiPieceType.chariot);
      expect(next.hidden.contains(to), isFalse);
    });
  });

  group('翻开的士象放宽', () {
    test('暗子在士位：按士的标准走法（九宫内斜行）', () {
      final hiddenAdvisor =
          XiangqiPiece(XiangqiColor.red, XiangqiPieceType.horse);
      final state = _state(
        {xiangqiIndex(9, 3): hiddenAdvisor},
        hidden: {xiangqiIndex(9, 3)},
      );
      expect(
        _targetsOf(jieqiLegalMoves(state), xiangqiIndex(9, 3)),
        {xiangqiIndex(8, 4)},
        reason: '第一步按点位棋种（士）走：九宫内斜行一格',
      );
    });

    test('翻开的士可出九宫 / 过河（斜行一格全盘）', () {
      final advisor = XiangqiPiece(XiangqiColor.red, XiangqiPieceType.advisor);
      final state = _state(
        {xiangqiIndex(5, 4): advisor},
        hidden: const {},
      );
      expect(
        _targetsOf(jieqiLegalMoves(state), xiangqiIndex(5, 4)),
        {
          xiangqiIndex(4, 3),
          xiangqiIndex(4, 5), // 过河
          xiangqiIndex(6, 3),
          xiangqiIndex(6, 5),
        },
        reason: '揭棋翻开的士 = 斜行一格全盘，不受九宫 / 河界限制',
      );
    });

    test('暗象在象位：标准走法（不过河）', () {
      final hiddenElephant =
          XiangqiPiece(XiangqiColor.red, XiangqiPieceType.chariot);
      final state = _state(
        {xiangqiIndex(9, 2): hiddenElephant},
        hidden: {xiangqiIndex(9, 2)},
      );
      expect(
        _targetsOf(jieqiLegalMoves(state), xiangqiIndex(9, 2)),
        {xiangqiIndex(7, 0), xiangqiIndex(7, 4)},
        reason: '象位暗子第一步走田且不过河（红方半场）',
      );
    });

    test('翻开的象可过河（保留塞象眼）', () {
      final elephant =
          XiangqiPiece(XiangqiColor.red, XiangqiPieceType.elephant);
      final state = _state(
        {xiangqiIndex(5, 2): elephant},
        hidden: const {},
      );
      final targets = _targetsOf(jieqiLegalMoves(state), xiangqiIndex(5, 2));
      expect(targets, contains(xiangqiIndex(3, 0)), reason: '翻开的象可以过河');
      expect(targets, contains(xiangqiIndex(7, 0)));
      // 塞象眼：在 (4,1) 放子 → (3,0) 被塞
      final blocked = _state(
        {
          xiangqiIndex(5, 2): elephant,
          xiangqiIndex(4, 1):
              XiangqiPiece(XiangqiColor.red, XiangqiPieceType.pawn),
        },
        hidden: const {},
      );
      expect(
        _targetsOf(jieqiLegalMoves(blocked), xiangqiIndex(5, 2)),
        isNot(contains(xiangqiIndex(3, 0))),
        reason: '塞象眼保留',
      );
    });

    test('走法不得吃将（士象放宽也不豁免）', () {
      final advisor = XiangqiPiece(XiangqiColor.red, XiangqiPieceType.advisor);
      final cells = List<int?>.filled(kXiangqiCells, null);
      cells[xiangqiIndex(0, 3)] = XiangqiPiece.blackGeneral.pack();
      cells[xiangqiIndex(0, 5)] = XiangqiPiece.blackAdvisor.pack();
      cells[xiangqiIndex(9, 4)] = XiangqiPiece.redGeneral.pack();
      cells[xiangqiIndex(1, 4)] = advisor.pack();
      final state = JieqiState(
        board: XiangqiBoardState(cells: cells, sideToMove: XiangqiColor.red),
        hidden: const {},
      );
      for (final m in jieqiLegalMoves(state)) {
        final target = state.board.pieceAt(m.to);
        expect(target?.isGeneral, isNot(isTrue),
            reason: '走法不得吃将：${m.fromName}${m.toName}');
      }
    });
  });

  group('将军判定（虚拟棋盘）', () {
    test('暗子的威胁按点位棋种算，不按真实棋种', () {
      // 黑暗子（真实棋种 = 兵）摆红方车位 (9,0) —— 点位棋种车。
      // 红帅 (9,4)，中间无子 → 车式攻击 = 红被将军；
      // 若按真实棋种（兵）判，则不被攻击。
      final blackHiddenPawn =
          XiangqiPiece(XiangqiColor.black, XiangqiPieceType.pawn);
      final state = _state(
        {xiangqiIndex(9, 0): blackHiddenPawn},
        hidden: {xiangqiIndex(9, 0)},
        side: XiangqiColor.red,
      );
      expect(jieqiIsInCheck(state, XiangqiColor.red), isTrue,
          reason: '车位暗子按车算威胁');
      expect(xiangqiIsInCheck(state.board, XiangqiColor.red), isFalse,
          reason: '对照组：标准引擎按真实棋种（兵）判 —— 差异正是虚拟棋盘存在的理由');
    });

    test('暗子被挡则不构成将军', () {
      final blackHiddenPawn =
          XiangqiPiece(XiangqiColor.black, XiangqiPieceType.pawn);
      final shield = XiangqiPiece(XiangqiColor.red, XiangqiPieceType.pawn);
      final state = _state(
        {
          xiangqiIndex(9, 0): blackHiddenPawn,
          xiangqiIndex(9, 2): shield,
        },
        hidden: {xiangqiIndex(9, 0)},
        side: XiangqiColor.red,
      );
      expect(jieqiIsInCheck(state, XiangqiColor.red), isFalse);
    });
  });

  group('合法性过滤（走后自己将不被攻击）', () {
    test('送将的暗子走法被过滤（炮式一屏：兵挪开仍被将军）', () {
      // 黑明炮 (4,4) 沿 col4 打红帅 (9,4)；红暗兵（真实棋种马）在 (6,4)
      // 当炮架：屏恰一 → 帅被将军。兵位暗马前进一步 (5,4) 后
      // 屏仍是恰一（(5,4) 成为新炮架）→ 仍被将军 → 非法；帅横移 (9,3) 合法。
      final blackCannon = XiangqiPiece(XiangqiColor.black, XiangqiPieceType.cannon);
      final hiddenPawn = XiangqiPiece(XiangqiColor.red, XiangqiPieceType.horse);
      final state = _state(
        {
          xiangqiIndex(4, 4): blackCannon,
          xiangqiIndex(6, 4): hiddenPawn,
        },
        hidden: {xiangqiIndex(6, 4)},
        side: XiangqiColor.red,
      );
      final moves = jieqiLegalMoves(state);
      expect(
        moves.any((m) =>
            m.from == xiangqiIndex(6, 4) && m.to == xiangqiIndex(5, 4)),
        isFalse,
        reason: '走后仍被将军（炮式一屏）→ 非法',
      );
      expect(
        moves.any((m) =>
            m.from == xiangqiIndex(9, 4) && m.to == xiangqiIndex(9, 3)),
        isTrue,
        reason: '帅离开受攻纵线 → 合法',
      );
    });

    test('暗子移动后「变脸」改变攻击关系（走后虚拟棋盘才算对）', () {
      // 黑暗马（车位）在 (0,0)：按车瞄 col0 / row0，不瞄红帅 (9,4)。
      // 红暗兵 (6,4) 前进一步 → 合法（无新增威胁）。
      final blackHiddenChariotRole =
          XiangqiPiece(XiangqiColor.black, XiangqiPieceType.horse);
      final hiddenPawn = XiangqiPiece(XiangqiColor.red, XiangqiPieceType.pawn);
      final state = _state(
        {
          xiangqiIndex(0, 0): blackHiddenChariotRole,
          xiangqiIndex(6, 4): hiddenPawn,
        },
        hidden: {
          xiangqiIndex(0, 0),
          xiangqiIndex(6, 4),
        },
        side: XiangqiColor.red,
      );
      expect(
        jieqiLegalMoves(state).any((m) =>
            m.from == xiangqiIndex(6, 4) && m.to == xiangqiIndex(5, 4)),
        isTrue,
      );
    });
  });

  group('终局判定', () {
    test('将死：三车锁帅', () {
      // 黑车 (8,4) 直攻红帅 (9,4)；黑车 (9,0) 封锁 row9；
      // 黑车 (8,8) 封锁 (8,4) 的吃将逃点 → 红无合法着 → 将死。
      final cells = List<int?>.filled(kXiangqiCells, null);
      cells[xiangqiIndex(9, 4)] = XiangqiPiece.redGeneral.pack();
      cells[xiangqiIndex(0, 4)] = XiangqiPiece.blackGeneral.pack();
      cells[xiangqiIndex(8, 4)] = XiangqiPiece.blackChariot.pack();
      cells[xiangqiIndex(9, 0)] = XiangqiPiece.blackChariot.pack();
      cells[xiangqiIndex(8, 8)] = XiangqiPiece.blackChariot.pack();
      final state = JieqiState(
        board: XiangqiBoardState(cells: cells, sideToMove: XiangqiColor.red),
        hidden: const {},
      );
      final st = jieqiStatus(state);
      expect(st.outcome, XiangqiOutcome.blackWins);
      expect(st.reason, XiangqiEndReason.checkmate);
    });

    test('正常局面 → playing', () {
      final state = _state(
        {
          xiangqiIndex(6, 0):
              XiangqiPiece(XiangqiColor.red, XiangqiPieceType.pawn),
        },
        hidden: {xiangqiIndex(6, 0)},
      );
      expect(jieqiStatus(state).outcome, XiangqiOutcome.playing);
    });
  });

  group('棋谱重放（暗子集合逐手收缩）', () {
    test('走过的暗子翻开且保持翻开；被吃暗子离场', () {
      final init = boardStateFromFen(_kXiangqiLikeFen);
      final j0 = JieqiState(
        board: init,
        hidden: jieqiInitialHidden(init),
      );
      // 红兵 (6,0) 前进三步吃黑卒 (3,0)：a6a5 / a5a4 / a4a3
      final states = jieqiReplayStates(j0, ['a6a5', 'a5a4', 'a4a3']);
      expect(states.length, 4);
      expect(states[0].hidden.length, 30);
      expect(states[1].hidden.contains(xiangqiIndex(6, 0)), isFalse,
          reason: 'a6a5 走过的暗子当场翻开');
      expect(states[1].hidden.length, 29);
      expect(states[2].hidden.length, 29, reason: '明子再走不影响暗子集合');
      expect(states[3].hidden.length, 28, reason: 'a4a3 吃掉黑方暗卒 → 离场');
      expect(states[3].hidden.contains(xiangqiIndex(3, 0)), isFalse);
    });

    test('坏记号 / 起点无子 → 抛异常（调用方降级）', () {
      final init = boardStateFromFen(_kXiangqiLikeFen);
      final j0 = JieqiState(
        board: init,
        hidden: jieqiInitialHidden(init),
      );
      expect(() => jieqiReplayStates(j0, ['zzzz']), throwsFormatException);
      // e4 = (4,4) 是空格 → 起点无子
      expect(() => jieqiReplayStates(j0, ['e4e5']), throwsArgumentError);
    });
  });
}
