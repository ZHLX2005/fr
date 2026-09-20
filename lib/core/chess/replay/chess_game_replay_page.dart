// lib/core/chess/replay/chess_game_replay_page.dart
//
// 整局离线回放页 —— 从对局回放库（ChessGameRecordListPage）进入。
//
// 布局（竖屏单列）：
//   AppBar(title: 对局标题, actions: 终局徽标)
//   [截断提示条]（谱尾 N 手解析失败时）
//   Expanded：棋盘（只读，随屏自适应，回放局面 + 上一步高亮）
//   快照横向列表：开局 / 第 N 手 / 终局 每步一档缩略棋盘，
//     点选任意快照 → 直接跳到该局面（"从某快照开始"核心交互）
//   ChessReplayBar：步进 / 自动播放 / 进度条 / 退出（复用房间页控件）
//
// 回放状态与 ChessRoomPage 的回放段语义一致（默认从终局开始、
// 自动播放到终局停止、终局按 ▶ 从头重放），但独立于房间页实现：
//   数据源 = ChessGameRecord（本地持久化），非服务端快照。

import 'dart:async';

import 'package:flutter/material.dart';

import '../skins/chess_skin.dart';
import '../widgets/chess_board.dart';
import '../widgets/chess_replay_bar.dart';
import 'chess_game_record.dart';
import 'chess_replay_resolver.dart';

/// 整局离线回放页。
class ChessGameReplayPage extends StatefulWidget {
  /// 已保存的对局记录（本地回放库条目）。
  final ChessGameRecord record;

  /// 缩略 / 主棋盘皮肤。null → ChessSkinBundle.byId('1')。
  final ChessSkin? skin;

  const ChessGameReplayPage({
    super.key,
    required this.record,
    this.skin,
  });

  @override
  State<ChessGameReplayPage> createState() => _ChessGameReplayPageState();
}

class _ChessGameReplayPageState extends State<ChessGameReplayPage> {
  /// 自动播放节奏（与房间页回放一致）。
  static const Duration _kTickInterval = Duration(milliseconds: 800);

  ChessSkin get _skin =>
      widget.skin ?? ChessSkinBundle.byId('1');

  /// 重演结果（initState 一次构建，步进 / 跳转全 O(1)）。
  late final ChessReplayResult _replay;

  /// 当前回放到第几步（0 = 初始局面，_replay.moves.length = 终局）。
  late int _index;

  bool _playing = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _replay = ChessGameReplayResolver.resolve(
      initialFen: widget.record.initialFen,
      uciMoves: widget.record.uciMoves,
    );
    _index = _replay.moves.length; // 从终局开始（与房间页复盘一致）。
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ─────────────────────────── 回放控制 ───────────────────────────

  void _seek(int i) {
    final clamped = i.clamp(0, _replay.moves.length);
    if (clamped == _index && !_playing) return;
    if (_playing && clamped >= _replay.moves.length) {
      // 播放中拖到终局 → 停在终局并复位播放键（与房间页语义一致）。
      _timer?.cancel();
      _timer = null;
      setState(() {
        _index = clamped;
        _playing = false;
      });
      return;
    }
    setState(() => _index = clamped);
  }

  void _step(int delta) => _seek(_index + delta);

  void _togglePlay() {
    if (_playing) {
      _timer?.cancel();
      _timer = null;
      setState(() => _playing = false);
      return;
    }
    // 已在终局按 ▶ → 回到开局重放（标准复盘 UX）。
    final start = _index >= _replay.moves.length ? 0 : _index;
    setState(() {
      _index = start;
      _playing = true;
    });
    _timer = Timer.periodic(_kTickInterval, (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    final next = _index + 1;
    if (next >= _replay.moves.length) {
      _timer?.cancel();
      _timer = null;
      setState(() {
        _index = _replay.moves.length;
        _playing = false;
      });
      return;
    }
    setState(() => _index = next);
  }

  // ─────────────────────────── UI ───────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = _replay.states[_index];
    final lastMove =
        _index > 0 ? _replay.moves[_index - 1] : null;
    final statusLabel = chessGameStatusLabel(widget.record.status);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(widget.record.title, overflow: TextOverflow.ellipsis),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        actions: [
          if (statusLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                label: Text(statusLabel),
                visualDensity: VisualDensity.compact,
                labelStyle: const TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // 谱尾截断提示（畸形 / 脱节棋谱防御）。
          if (_replay.truncated > 0)
            Material(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_outlined,
                        size: 16,
                        color: theme.colorScheme.onErrorContainer),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '谱尾 ${_replay.truncated} 手无法解析，已回放到第 ${_replay.moves.length} 手',
                        style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // 棋盘：只读回放（无输入回调），随屏自适应。
          Expanded(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final side = constraints.biggest.shortestSide;
                  return Center(
                    child: SizedBox(
                      width: side,
                      height: side,
                      child: ChessBoard(
                        state: state,
                        skin: _skin,
                        sideToMove: state.sideToMove,
                        lastMove: lastMove,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          // 快照横向列表：点选任意一步直接跳到该局面。
          _buildSnapshotStrip(theme),
          // 回放控制条（保存 / 导出按钮不挂 —— 数据源已是回放库本体）。
          SafeArea(
            top: false,
            child: ChessReplayBar(
              index: _index,
              total: _replay.moves.length,
              playing: _playing,
              onToStart: () => _seek(0),
              onStepBack: () => _step(-1),
              onTogglePlay: _togglePlay,
              onStepForward: () => _step(1),
              onToEnd: () => _seek(_replay.moves.length),
              onSeek: _seek,
              onExit: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      ),
    );
  }

  /// 快照横向列表：每步一档（开局 / 第 N 手 / 终局）。
  ///
  /// ListView.builder 懒加载（长对局 40+ 缩略棋盘不卡）；
  /// 当前 index 高亮描边；点击 = _seek（播放中点快照 → 从该快照继续播放）。
  Widget _buildSnapshotStrip(ThemeData theme) {
    final total = _replay.moves.length;
    return SizedBox(
      // 72 缩略棋盘 + 2 间距 + 1 行标签 + 边框 + 上下 padding → 需 ≥132。
      height: 132,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: total + 1,
        itemBuilder: (context, i) {
          final selected = i == _index;
          final label = i == 0
              ? '开局'
              : (i == total ? '终局 · $i' : '第 $i 手');
          final boardState = _replay.states[i];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _seek(i),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    width: selected ? 2 : 1,
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.dividerColor.withValues(alpha: 0.5),
                  ),
                  color: selected
                      ? theme.colorScheme.primaryContainer
                          .withValues(alpha: 0.3)
                      : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 72,
                      height: 72,
                      child: ChessBoard(
                        state: boardState,
                        skin: _skin,
                        sideToMove: boardState.sideToMove,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
