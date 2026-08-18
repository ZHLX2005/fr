import 'dart:async';

import 'package:flutter/material.dart';

import '../board.dart' show GomokuBoardWidget;
import '../engine.dart' show GomokuRoom;
import 'gomoku_opening_catalog.dart' show gomokuOpeningCases;
import 'gomoku_opening_models.dart';

class GomokuOpeningPlayer extends StatefulWidget {
  const GomokuOpeningPlayer({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  State<GomokuOpeningPlayer> createState() => _GomokuOpeningPlayerState();
}

class _GomokuOpeningPlayerState extends State<GomokuOpeningPlayer> {
  int _caseIndex = 0;
  GomokuOpeningPlayerState _player = const GomokuOpeningPlayerState();
  Timer? _timer;

  GomokuOpeningCase get _case => gomokuOpeningCases[_caseIndex];

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _selectCase(int index) {
    _timer?.cancel();
    setState(() {
      _caseIndex = index;
      _player = const GomokuOpeningPlayerState();
    });
  }

  void _reset() {
    _timer?.cancel();
    setState(() => _player = const GomokuOpeningPlayerState());
  }

  void _step(int delta) {
    final next = (_player.step + delta).clamp(0, _case.moves.length).toInt();
    setState(() {
      _player = _player.copyWith(step: next, autoPlaying: false);
    });
    if (next == _case.moves.length) _timer?.cancel();
  }

  void _playRecommended(Offset position, double side) {
    if (_player.autoPlaying || _player.step >= _case.moves.length) return;
    const padding = 16.0;
    final step = (side - padding * 2) / 14;
    final move = _case.moves[_player.step];
    final x = ((position.dx - padding) / step).round();
    final y = ((position.dy - padding) / step).round();
    if (x == move.x && y == move.y) _step(1);
  }

  void _toggleAutoPlay() {
    if (_player.autoPlaying) {
      _timer?.cancel();
      setState(() => _player = _player.copyWith(autoPlaying: false));
      return;
    }
    if (_player.step >= _case.moves.length) {
      setState(() => _player = const GomokuOpeningPlayerState());
    }
    setState(() => _player = _player.copyWith(autoPlaying: true));
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 850), (_) {
      if (!mounted || _player.step >= _case.moves.length) {
        _timer?.cancel();
        if (mounted) {
          setState(() => _player = _player.copyWith(autoPlaying: false));
        }
        return;
      }
      setState(() => _player = _player.copyWith(step: _player.step + 1));
    });
  }

  @override
  Widget build(BuildContext context) {
    final moves = _case.moves.take(_player.step).toList();
    final board = GomokuRoom.rebuildBoard(moves);
    final last = moves.isEmpty ? null : (moves.last.x, moves.last.y);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('开局学习'),
        leading: IconButton(
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                itemCount: gomokuOpeningCases.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) => ChoiceChip(
                  label: Text(gomokuOpeningCases[index].title),
                  selected: index == _caseIndex,
                  onSelected: (_) => _selectCase(index),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _case.noteAt(_player.step),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ),
            Expanded(
              child: Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final side = constraints.biggest.shortestSide;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (details) =>
                          _playRecommended(details.localPosition, side),
                      child: GomokuBoardWidget(
                        board: board,
                        lastMove: last,
                        validMoves: _player.step < _case.moves.length
                            ? {
                                (
                                  _case.moves[_player.step].x,
                                  _case.moves[_player.step].y,
                                ),
                              }
                            : const {},
                      ),
                    );
                  },
                ),
              ),
            ),
            Text('第 ${_player.step} / ${_case.moves.length} 手'),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _player.step == 0 ? null : () => _step(-1),
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('上一步'),
                  ),
                  FilledButton.icon(
                    onPressed: _player.step >= _case.moves.length
                        ? null
                        : () => _step(1),
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('下一步'),
                  ),
                  IconButton(
                    tooltip: _player.autoPlaying ? '暂停' : '自动播放',
                    onPressed: _toggleAutoPlay,
                    icon: Icon(
                      _player.autoPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                  ),
                  IconButton(
                    tooltip: '重置',
                    onPressed: _reset,
                    icon: const Icon(Icons.replay),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
