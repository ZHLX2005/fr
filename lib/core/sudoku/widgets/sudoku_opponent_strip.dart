// lib/core/sudoku/widgets/sudoku_opponent_strip.dart
//
// 双玩家信息条：双方昵称 + 计时 + 完成度（已填格数 / 总数）。
//
// 横向 Row，分隔线居中。背景走 context.colors.surface，文字走 context.colors.text。
//
// 进度条：用 LinearProgressIndicator 显示完成百分比；
//   · 当前玩家：context.colors.accent（自己）
//   · 对手：context.colors.textMuted（弱色）
// 完成时（filledCount == 81）：progress 显示 100%，并加 ✓ 图标提示。

import 'package:flutter/material.dart';

import '../../../widgets/context_colors.dart';
import 'sudoku_error_badge.dart';

/// 单方玩家信息：昵称 + 已填数 + 错误数 + 是否完成。
class SudokuPlayerInfo {
  final String name;
  final int filledCount;
  final int errorCount;
  final bool isComplete;
  final Duration? elapsed;

  const SudokuPlayerInfo({
    required this.name,
    this.filledCount = 0,
    this.errorCount = 0,
    this.isComplete = false,
    this.elapsed,
  });
}

class SudokuOpponentStrip extends StatelessWidget {
  final SudokuPlayerInfo self;
  final SudokuPlayerInfo opponent;
  final int totalCells;

  const SudokuOpponentStrip({
    super.key,
    required this.self,
    required this.opponent,
    this.totalCells = 81,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(color: colors.outline.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          Expanded(child: _buildPlayerColumn(context, self, isSelf: true)),
          Container(
            width: 1,
            height: 40,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: colors.outline.withValues(alpha: 0.3),
          ),
          Expanded(child: _buildPlayerColumn(context, opponent, isSelf: false)),
        ],
      ),
    );
  }

  Widget _buildPlayerColumn(
    BuildContext context,
    SudokuPlayerInfo info, {
    required bool isSelf,
  }) {
    final colors = context.colors;
    final progress = totalCells == 0 ? 0.0 : info.filledCount / totalCells;
    final progressColor = isSelf ? colors.accent : colors.textMuted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                info.name,
                style: TextStyle(
                  color: colors.text,
                  fontSize: 14,
                  fontWeight: isSelf ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (info.isComplete)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(Icons.check_circle, color: colors.accent, size: 14),
              ),
            const SizedBox(width: 4),
            SudokuErrorBadge(errorCount: info.errorCount),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            backgroundColor: colors.outline.withValues(alpha: 0.2),
            valueColor: AlwaysStoppedAnimation(progressColor),
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${info.filledCount}/$totalCells',
              style: TextStyle(color: colors.textMuted, fontSize: 11),
            ),
            if (info.elapsed != null)
              Text(
                _formatDuration(info.elapsed!),
                style: TextStyle(color: colors.textMuted, fontSize: 11),
              ),
          ],
        ),
      ],
    );
  }

  static String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
