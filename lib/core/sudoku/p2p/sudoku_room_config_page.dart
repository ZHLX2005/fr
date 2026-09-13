// lib/core/sudoku/p2p/sudoku_room_config_page.dart
//
// 数独准备阶段规则面板（嵌入 lobby/ready 卡，非全屏页面）。
//
// host 视图：难度 radio + 「生成题目」按钮 + 生成状态。
// guest 视图：只读展示当前难度 + 「题已生成」状态。
//
// 与 ChessRoomRulesPanel 同样的对偶模式（editable=true → host 可改；
// editable=false → guest 只读），回调由父级（任务 9 的 room page）接到
// SET_RULES action。本面板不直接调用 SudokuGenerator —— 生成职责归 caller。

import 'package:flutter/material.dart';

import '../models/sudoku_puzzle.dart';
import '../../../widgets/context_colors.dart';

/// 房间规则结果 —— 映射到 SET_RULES / 历史 initialParams。
@immutable
class SudokuRoomConfig {
  /// 'easy' / 'medium' / 'hard'。
  final String difficulty;

  /// host 生成后填入；guest 端由快照同步。
  final SudokuPuzzle? puzzle;

  const SudokuRoomConfig({required this.difficulty, this.puzzle});

  @override
  String toString() =>
      'SudokuRoomConfig(difficulty: $difficulty, puzzleReady: ${puzzle != null})';
}

/// 准备阶段规则面板 —— 可嵌入 lobby/ready 卡片。
///
/// [editable]=true（host）时 radio / 按钮可交互；guest 只读展示。
class SudokuRoomConfigPanel extends StatefulWidget {
  final bool editable;
  final String difficulty;
  final bool puzzleReady;
  final void Function(String difficulty)? onDifficultyChanged;
  final VoidCallback? onGenerate;

  const SudokuRoomConfigPanel({
    super.key,
    required this.editable,
    required this.difficulty,
    required this.puzzleReady,
    this.onDifficultyChanged,
    this.onGenerate,
  });

  @override
  State<SudokuRoomConfigPanel> createState() => _SudokuRoomConfigPanelState();
}

class _SudokuRoomConfigPanelState extends State<SudokuRoomConfigPanel> {
  static const _difficulties = [
    ('easy', '简单 (35 格)'),
    ('medium', '中等 (30 格)'),
    ('hard', '困难 (25 格)'),
  ];

  String _labelFor(String value) {
    for (final d in _difficulties) {
      if (d.$1 == value) return d.$2;
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.editable ? '难度（仅房主可改）' : '难度',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
            ),
            const SizedBox(height: 4),
            if (widget.editable) ...[
              ..._difficulties.map((d) => RadioListTile<String>(
                    value: d.$1,
                    groupValue: widget.difficulty,
                    title: Text(d.$2),
                    onChanged: widget.onDifficultyChanged != null
                        ? (v) => widget.onDifficultyChanged!(v!)
                        : null,
                  )),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: widget.onGenerate,
                icon: const Icon(Icons.refresh),
                label: const Text('生成题目'),
              ),
            ] else
              Text(
                _labelFor(widget.difficulty),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            if (widget.puzzleReady)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '✓ 题已生成，等待双方准备',
                  style: TextStyle(
                    color: colors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else if (!widget.editable)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '等待 host 生成题目…',
                  style: TextStyle(color: colors.textMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
