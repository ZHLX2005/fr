// lib/core/chess/widgets/chess_replay_bar.dart
//
// 对局回放控制条（复盘）—— 无状态控件，父层（ChessRoomPage）持有回放状态。
//
// 职责：只渲染控制 UI + 透传回调，不持有任何回放状态：
//   · |<（回到开局）/ <（上一步）/ ▶-⏸（自动播放开关）/ >（下一步）/ >|（跳到终局）
//   · 步数标签 "12 / 40"（0 = 初始局面，total = 终局）
//   · 拖动进度条（Slider 离散 = 每步一档）
//   · 退出回放（回到终局覆盖层）
//
// 边界禁用：index == 0 禁 |< 和 <；index == total 禁 > 和 >|。
// 自动播放到终局后由父层把 playing 置 false（播放键复位 ▶）；
// 在终局按 ▶ 由父层从头重放（标准复盘 UX）。
//
// 不负责：
//   · 回放状态推进 / 计时器（ChessRoomPage 持有）
//   · 局面重演（ChessRoomPage._enterReplay 一次性构建局面子序列）
//
// 颜色走 context.chessColors（v6.2.1 第 6 strategy 通道）。

import 'package:flutter/material.dart';

import '../../../widgets/context_chess_colors.dart';

/// 对局回放控制条（|< < ▶/⏸ > >| + 步数 + 进度条 + 退出）。
class ChessReplayBar extends StatelessWidget {
  /// 当前回放到第几步（0 = 初始局面，total = 终局）。
  final int index;

  /// 总步数（= 走法总数；进度条 max）。
  final int total;

  /// 自动播放中（true 显示 ⏸，false 显示 ▶）。
  final bool playing;

  /// |< 回到开局（index 0）。
  final VoidCallback onToStart;

  /// < 上一步。
  final VoidCallback onStepBack;

  /// ▶/⏸ 自动播放开关。
  final VoidCallback onTogglePlay;

  /// > 下一步。
  final VoidCallback onStepForward;

  /// >| 跳到终局（index = total）。
  final VoidCallback onToEnd;

  /// 拖动进度条（0..total，离散每步一档）。
  final ValueChanged<int> onSeek;

  /// 退出回放（回到终局覆盖层）。
  final VoidCallback onExit;

  const ChessReplayBar({
    super.key,
    required this.index,
    required this.total,
    required this.playing,
    required this.onToStart,
    required this.onStepBack,
    required this.onTogglePlay,
    required this.onStepForward,
    required this.onToEnd,
    required this.onSeek,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.chessColors;
    final atStart = index <= 0;
    final atEnd = index >= total;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 步进按钮排：|< < ▶/⏸ > >| + 步数标签（边界禁用）
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: '回到开局',
              onPressed: atStart ? null : onToStart,
              icon: const Icon(Icons.first_page),
            ),
            IconButton(
              tooltip: '上一步',
              onPressed: atStart ? null : onStepBack,
              icon: const Icon(Icons.chevron_left),
            ),
            // ▶/⏸：自动播放开关（终局按 ▶ 由父层从头重放）
            IconButton.filled(
              tooltip: playing ? '暂停' : '自动播放',
              onPressed: onTogglePlay,
              icon: Icon(playing ? Icons.pause : Icons.play_arrow),
            ),
            IconButton(
              tooltip: '下一步',
              onPressed: atEnd ? null : onStepForward,
              icon: const Icon(Icons.chevron_right),
            ),
            IconButton(
              tooltip: '跳到终局',
              onPressed: atEnd ? null : onToEnd,
              icon: const Icon(Icons.last_page),
            ),
            const SizedBox(width: 8),
            // 步数标签："12 / 40"（0 = 初始局面）
            Text(
              '$index / $total',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.coordinateLabel,
              ),
            ),
          ],
        ),
        // 拖动进度条：离散 total 档（每步一档），可来回拖到任意步
        Slider(
          value: index.toDouble(),
          max: total.toDouble(),
          divisions: total,
          label: '$index',
          activeColor: colors.selectedSquare,
          inactiveColor: colors.gridLine,
          onChanged: (v) => onSeek(v.round()),
        ),
        // 退出回放：回到终局覆盖层（返回 / 再来一局 / 复盘）
        OutlinedButton.icon(
          onPressed: onExit,
          icon: const Icon(Icons.close, size: 18),
          label: const Text('退出回放'),
        ),
      ],
    );
  }
}
