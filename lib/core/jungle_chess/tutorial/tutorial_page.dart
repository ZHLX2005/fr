// lib/core/jungle_chess/tutorial/tutorial_page.dart
//
// 规则教程：在**真实棋盘**上逐步演示。
//
// 关键设计：演示走法交给 [JungleEngine.movePiece] 真正执行，而不是另写一套动画脚本。
// 教程里能走出来的，实战一定也能走；引擎改了规则，教程立刻跟着变 —— 不存在
// "教程说能走、实战走不了"的漂移。反例（象吃鼠这类不合法走法）标 blocked，
// 只画一个 ✗，不推进棋局。

import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/jungle_constants.dart';
import '../engine/jungle_engine.dart';
import '../models/game_state.dart';
import '../models/piece.dart';
import '../widgets/jungle_board.dart';
import '../widgets/jungle_board_frame.dart';
import 'tutorial_steps.dart';

class JungleTutorialPage extends StatefulWidget {
  const JungleTutorialPage({super.key});

  @override
  State<JungleTutorialPage> createState() => _JungleTutorialPageState();
}

class _JungleTutorialPageState extends State<JungleTutorialPage> {
  int _chapter = 0;

  /// 已演示的步数。0 = 起始局面，n = 已走完前 n 步。
  int _step = 0;

  Timer? _timer;

  TutorialChapter get _ch => kTutorialChapters[_chapter];
  int get _total => _ch.moves.length;
  bool get _playing => _timer != null;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ═══════════════════════ 播放控制 ═══════════════════════

  void _selectChapter(int i) {
    _stop();
    setState(() {
      _chapter = i;
      _step = 0;
    });
  }

  void _next() {
    if (_step >= _total) {
      _stop();
      return;
    }
    setState(() => _step++);
    if (_step >= _total) _stop();
  }

  void _prev() {
    _stop();
    if (_step == 0) return;
    setState(() => _step--);
  }

  void _togglePlay() {
    if (_playing) {
      _stop();
      return;
    }
    if (_total == 0) return;
    // 播放到头了 → 从头再演一遍
    if (_step >= _total) setState(() => _step = 0);
    setState(() {
      _timer = Timer.periodic(kTutorialStepDuration, (_) => _next());
    });
  }

  void _stop() {
    if (_timer == null) return;
    _timer!.cancel();
    _timer = null;
    if (mounted) setState(() {});
  }

  // ═══════════════════════ 局面推演 ═══════════════════════

  /// 从章节起始局面重放前 [_step] 步，得到当前应展示的棋局。
  ///
  /// 每次重放而不是增量维护：步进/回退/换章共用一条路径，不会出现状态残留。
  GameState _currentState() {
    var s = _ch.initialState();
    for (var i = 0; i < _step; i++) {
      final m = _ch.moves[i];
      if (m.blocked) continue; // 反例不改变棋局
      final next = JungleEngine.movePiece(s, m.from, m.to);
      if (next != null) s = next;
    }
    return s;
  }

  /// 棋盘高亮 = 章节地形高亮 + 当前这一步的轨迹
  Map<int, Color> _currentHighlights() {
    final map = Map<int, Color>.from(_ch.highlights);
    if (_step == 0) return map;
    final m = _ch.moves[_step - 1];
    if (m.blocked) {
      map[m.from.index] = kHintTrailFrom;
      map[m.to.index] = kHintFocus;
    } else {
      map[m.from.index] = kHintTrailFrom;
      map[m.to.index] = kHintTrailTo;
    }
    return map;
  }

  TutorialMove? get _currentMove => _step == 0 ? null : _ch.moves[_step - 1];

  // ═══════════════════════ UI ═══════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPageBg(context),
      appBar: AppBar(
        title: const Text(
          '斗兽棋规则教程',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: kTextStrong(context),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildChapterBar(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 7 / 9,
                    child: JungleBoardFrame(
                      child: JungleBoard(
                        gameState: _currentState(),
                        highlightCells: _currentHighlights(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _buildCaption(),
            _buildControls(),
          ],
        ),
      ),
    );
  }

  /// 章节切换条
  Widget _buildChapterBar() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: kTutorialChapters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final active = i == _chapter;
          return GestureDetector(
            onTap: () => _selectChapter(i),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: active
                    ? kBluePieceTint.withValues(alpha: 0.10)
                    : Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: active
                      ? kBluePieceTint.withValues(alpha: 0.55)
                      : kPanelBorder(context),
                  width: active ? 1.5 : 1,
                ),
              ),
              child: Text(
                '${i + 1}. ${kTutorialChapters[i].title}',
                style: TextStyle(
                  color: active ? kBluePieceTint : kTextNormal(context),
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 旁白：未开始演示时显示章节规则说明，演示中显示当前这一步的解说
  Widget _buildCaption() {
    final move = _currentMove;
    final blocked = move?.blocked ?? false;
    final accent = blocked ? kRedPieceTint : kBluePieceTint;

    return Container(
      height: 108,
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: move == null ? Theme.of(context).colorScheme.surface : accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(kPanelRadius),
        border: Border.all(
          color: move == null ? kPanelBorder(context) : accent.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            move == null
                ? Icons.menu_book_rounded
                : (blocked ? Icons.block_rounded : Icons.play_arrow_rounded),
            size: 18,
            color: move == null ? kTextMuted(context) : accent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                move?.caption ?? _ch.summary,
                style: TextStyle(
                  color: move == null ? kTextNormal(context) : kTextStrong(context),
                  fontSize: 13.5,
                  height: 1.55,
                  fontWeight:
                      move == null ? FontWeight.w400 : FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 上一步 / 播放 / 下一步
  Widget _buildControls() {
    final hasMoves = _total > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          _CtrlButton(
            icon: Icons.skip_previous_rounded,
            label: '上一步',
            tint: kTextNormal(context),
            onTap: _step > 0 ? _prev : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _CtrlButton(
              icon: _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              label: hasMoves
                  ? (_playing ? '暂停' : '自动播放  $_step/$_total')
                  : '本章无演示',
              tint: kBluePieceTint,
              onTap: hasMoves ? _togglePlay : null,
            ),
          ),
          const SizedBox(width: 10),
          _CtrlButton(
            icon: Icons.skip_next_rounded,
            label: '下一步',
            tint: kBluePieceTint,
            onTap: _step < _total ? _next : null,
          ),
        ],
      ),
    );
  }
}

/// 边框强调式控制按钮：浅 tint 底 + 同色描边 + 同色前景
class _CtrlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback? onTap;

  const _CtrlButton({
    required this.icon,
    required this.label,
    required this.tint,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final c = enabled ? tint : kTextMuted(context).withValues(alpha: 0.55);
    return Material(
      color: enabled ? c.withValues(alpha: 0.08) : Theme.of(context).colorScheme.surface.withValues(alpha: 0.0),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: c),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: TextStyle(
                      color: c,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
