// lib/core/jungle_chess/tutorial/tutorial_steps.dart
//
// 教程章节数据。纯数据 + 纯构造，不含任何 UI。
//
// 每章给一个精简开局（[TutorialChapter.setup]）与一串演示走法。演示走法交给
// [JungleEngine.movePiece] 真正执行 —— 讲解与实际规则同源，不会出现"教程说能走、
// 实战走不了"的漂移。若某一步本来就**不合法**（用来讲反例，例如象吃鼠、鼠上岸吃子、
// 水路被鼠堵住的狮跳），把它标成 [TutorialMove.blocked]：只画一个 ✗ 提示，
// 不推进棋局，也不换手。
//
// 约定：同一章的 setup 里不能出现两颗「同色同动物」的棋子 —— 棋盘用
// `颜色_动物` 作为动画 key，重复会导致位移动画错乱。

import 'package:flutter/material.dart';

import '../constants/jungle_constants.dart';
import '../engine/jungle_engine.dart';
import '../models/game_state.dart';
import '../models/piece.dart';

/// 演示中的一步
class TutorialMove {
  final Coord from;
  final Coord to;

  /// 这一步的旁白
  final String caption;

  /// true = 这是个**反例**：该走法不合法，只提示不执行
  final bool blocked;

  const TutorialMove({
    required this.from,
    required this.to,
    required this.caption,
    this.blocked = false,
  });
}

/// 一个教程章节
class TutorialChapter {
  /// 章节标题（顶部 chip 文案）
  final String title;

  /// 章节规则说明（未开始演示时显示）
  final String summary;

  /// 起始摆子；为 null 表示用标准开局
  final List<Piece>? setup;

  /// 先手方
  final PlayerColor firstTurn;

  /// 演示走法序列
  final List<TutorialMove> moves;

  /// 要点亮的格子：1D index → 覆盖色
  final Map<int, Color> highlights;

  const TutorialChapter({
    required this.title,
    required this.summary,
    required this.moves,
    this.setup,
    this.firstTurn = PlayerColor.blue,
    this.highlights = const {},
  });

  /// 构造本章的起始棋局
  GameState initialState() {
    final s = setup;
    if (s == null) return JungleEngine.createInitialState();
    return GameState(
      pieces: {for (final p in s) p.position.index: p},
      currentTurn: firstTurn,
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 摆子小工具
// ══════════════════════════════════════════════════════════════

Piece _blue(int row, int col, Animal a) =>
    Piece(animal: a, color: PlayerColor.blue, position: (row: row, col: col));

Piece _red(int row, int col, Animal a) =>
    Piece(animal: a, color: PlayerColor.red, position: (row: row, col: col));

Coord _at(int row, int col) => (row: row, col: col);

/// 河流 / 陷阱 / 兽穴的整片高亮，讲棋盘时用
final Map<int, Color> _kTerrainHighlights = {
  for (final i in kRiverCells) i: kHintRiver,
  for (final i in kBlueTraps) i: kHintTrap,
  for (final i in kRedTraps) i: kHintTrap,
  kBlueDen: kHintDen,
  kRedDen: kHintDen,
};

final Map<int, Color> _kRiverHighlights = {
  for (final i in kRiverCells) i: kHintRiver,
};

final Map<int, Color> _kRedTrapHighlights = {
  for (final i in kRedTraps) i: kHintTrap,
};

const Map<int, Color> _kDenHighlights = {
  kBlueDen: kHintDen,
  kRedDen: kHintDen,
};

// ══════════════════════════════════════════════════════════════
// 章节
// ══════════════════════════════════════════════════════════════

final List<TutorialChapter> kTutorialChapters = [
  // ── 1. 棋盘与目标 ────────────────────────────────────────────
  TutorialChapter(
    title: '棋盘与目标',
    summary: '棋盘 7 列 × 9 行。蓝方在下，红方在上。\n\n'
        '• 绿色两格是双方的兽穴，把任意一颗棋子走进对方兽穴就赢。\n'
        '• 兽穴周围三格橙色是陷阱，敌方棋子踩上去等级归 0。\n'
        '• 中间蓝色六格是河，只有鼠能下水，狮和虎能跳过去。',
    highlights: _kTerrainHighlights,
    moves: const [],
  ),

  // ── 2. 基本走法 ──────────────────────────────────────────────
  TutorialChapter(
    title: '基本走法',
    summary: '双方轮流走子，每次把一颗自己的棋子沿上下左右移动一格。'
        '不能斜走，不能一次走两格（狮虎跳河除外）。',
    setup: [
      _blue(6, 3, Animal.wolf),
      _red(2, 3, Animal.wolf),
    ],
    moves: [
      TutorialMove(
        from: _at(6, 3),
        to: _at(7, 4),
        caption: '斜着走是不允许的',
        blocked: true,
      ),
      TutorialMove(from: _at(6, 3), to: _at(5, 3), caption: '蓝狼向前一格'),
      TutorialMove(from: _at(2, 3), to: _at(3, 3), caption: '轮到红方，红狼也向前一格'),
      TutorialMove(from: _at(5, 3), to: _at(4, 3), caption: '两狼逼近，同级可以互吃'),
    ],
  ),

  // ── 3. 等级与吃子 ────────────────────────────────────────────
  TutorialChapter(
    title: '等级与吃子',
    summary: '等级由大到小：象 8 › 狮 7 › 虎 6 › 豹 5 › 狼 4 › 狗 3 › 猫 2 › 鼠 1。\n\n'
        '走到相邻的敌方棋子上即可吃掉它，条件是**自己的等级不低于对方**。'
        '同级可以互吃，等级低的只能躲。',
    setup: [
      _blue(5, 3, Animal.lion),
      _blue(6, 0, Animal.dog),
      _red(4, 3, Animal.wolf),
      _red(5, 0, Animal.cat),
    ],
    moves: [
      TutorialMove(from: _at(6, 0), to: _at(5, 0), caption: '狗 3 级 ≥ 猫 2 级 → 吃掉红猫'),
      TutorialMove(from: _at(4, 3), to: _at(3, 3), caption: '狼 4 级打不过狮 7 级，只能后退'),
      TutorialMove(from: _at(5, 3), to: _at(4, 3), caption: '蓝狮继续压上'),
    ],
  ),

  // ── 4. 鼠吃象 · 象不吃鼠 ─────────────────────────────────────
  TutorialChapter(
    title: '鼠吃象',
    summary: '唯一的例外：最小的鼠可以吃掉最大的象，而象吃不了鼠。\n\n'
        '（除非鼠踩在象方的陷阱里，等级归 0 后象就能吃它了。）',
    setup: [
      _blue(5, 3, Animal.rat),
      _blue(3, 0, Animal.elephant),
      _red(4, 3, Animal.elephant),
      _red(2, 0, Animal.rat),
    ],
    moves: [
      TutorialMove(
        from: _at(3, 0),
        to: _at(2, 0),
        caption: '蓝象想吃红鼠 —— 不行，象吃不了鼠',
        blocked: true,
      ),
      TutorialMove(from: _at(5, 3), to: _at(4, 3), caption: '反过来，蓝鼠一口吃掉红象'),
      TutorialMove(from: _at(2, 0), to: _at(3, 0), caption: '红鼠同样能吃掉蓝象'),
    ],
  ),

  // ── 5. 鼠与河 ────────────────────────────────────────────────
  TutorialChapter(
    title: '鼠与河',
    summary: '中间六格是河。鼠是唯一能下水的棋子，可以自由进出。\n\n'
        '水里的鼠吃不到岸上的棋子，岸上的棋子也吃不到水里的鼠；'
        '但同在水里的两只鼠可以互吃。',
    highlights: _kRiverHighlights,
    setup: [
      _blue(6, 1, Animal.rat),
      _blue(6, 4, Animal.elephant),
      _red(2, 1, Animal.rat),
      _red(5, 0, Animal.dog),
    ],
    moves: [
      TutorialMove(from: _at(6, 1), to: _at(5, 1), caption: '蓝鼠下水'),
      TutorialMove(from: _at(2, 1), to: _at(3, 1), caption: '红鼠也下水'),
      TutorialMove(
        from: _at(6, 4),
        to: _at(5, 4),
        caption: '象想进河 —— 不行，除了鼠谁都不能下水',
        blocked: true,
      ),
      TutorialMove(
        from: _at(5, 1),
        to: _at(5, 0),
        caption: '水里的鼠想吃岸上的红狗 —— 隔水吃子不成立',
        blocked: true,
      ),
      TutorialMove(from: _at(5, 1), to: _at(4, 1), caption: '蓝鼠在水里游动'),
      TutorialMove(from: _at(3, 1), to: _at(4, 1), caption: '同在水中，红鼠吃掉蓝鼠'),
    ],
  ),

  // ── 6. 狮虎跳河 ──────────────────────────────────────────────
  TutorialChapter(
    title: '狮虎跳河',
    summary: '狮和虎可以横着或竖着一跃跨过整片河，直接落在对岸。\n\n'
        '但只要水路上蹲着一只鼠，这一跳就被封死了。',
    highlights: _kRiverHighlights,
    setup: [
      _blue(6, 1, Animal.lion),
      _blue(5, 2, Animal.rat),
      _red(4, 3, Animal.tiger),
    ],
    moves: [
      TutorialMove(from: _at(6, 1), to: _at(2, 1), caption: '蓝狮竖向跨过三格水，落到对岸'),
      TutorialMove(from: _at(4, 3), to: _at(4, 6), caption: '红虎横向跨过两格水'),
      TutorialMove(from: _at(5, 2), to: _at(5, 1), caption: '蓝鼠游到狮的水路上'),
      TutorialMove(from: _at(4, 6), to: _at(3, 6), caption: '红虎换个位置'),
      TutorialMove(
        from: _at(2, 1),
        to: _at(6, 1),
        caption: '水路被鼠堵住 —— 狮跳不回去了',
        blocked: true,
      ),
    ],
  ),

  // ── 7. 陷阱降级 ──────────────────────────────────────────────
  TutorialChapter(
    title: '陷阱降级',
    summary: '兽穴周围三格是陷阱。敌方棋子一踏进去，等级立刻归 0，'
        '任何一颗己方棋子都能把它吃掉 —— 哪怕是猫吃象。\n\n'
        '踩自己家的陷阱没有任何影响。',
    highlights: _kRedTrapHighlights,
    setup: [
      _blue(2, 3, Animal.elephant),
      _blue(5, 3, Animal.dog),
      _red(1, 4, Animal.cat),
    ],
    moves: [
      TutorialMove(from: _at(2, 3), to: _at(1, 3), caption: '蓝象踏进红方陷阱，等级归 0'),
      TutorialMove(from: _at(1, 4), to: _at(1, 3), caption: '红猫轻松吃掉这头象'),
    ],
  ),

  // ── 8. 入穴取胜 ──────────────────────────────────────────────
  TutorialChapter(
    title: '入穴取胜',
    summary: '把任意一颗棋子走进对方兽穴，立刻获胜。\n\n'
        '兽穴三面都是陷阱，进攻必须先冒险踩过去。'
        '自己的兽穴则是禁区，己方棋子不能进。\n\n'
        '此外，一方棋子被吃光、或轮到走时无子可动，同样判负。',
    highlights: _kDenHighlights,
    setup: [
      _blue(2, 3, Animal.tiger),
      _blue(8, 2, Animal.dog),
      _red(6, 3, Animal.lion),
    ],
    moves: [
      TutorialMove(
        from: _at(8, 2),
        to: _at(8, 3),
        caption: '蓝狗想退进自家兽穴 —— 自己的兽穴进不得',
        blocked: true,
      ),
      TutorialMove(from: _at(2, 3), to: _at(1, 3), caption: '蓝虎踩过红方陷阱逼近'),
      TutorialMove(from: _at(6, 3), to: _at(7, 3), caption: '红狮也在逼近蓝穴'),
      TutorialMove(from: _at(1, 3), to: _at(0, 3), caption: '蓝虎攻入红穴 —— 蓝方获胜！'),
    ],
  ),
];
