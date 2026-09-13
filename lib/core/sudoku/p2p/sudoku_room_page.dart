// lib/core/sudoku/p2p/sudoku_room_page.dart
//
// 数独联机房间页（lobby / ready / playing / ended 四态路由）。
// 权威方：服务端 Lua 状态机。本地棋盘在 puzzle 出现后一次性构造。
// 填值走 SudokuValidator；提交扁平 81 格 → 服务端裁决。

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../widgets/context_colors.dart';
import '../engine/sudoku_generator.dart';
import '../engine/sudoku_validator.dart';
import '../models/sudoku_board.dart';
import '../models/sudoku_puzzle.dart';
import '../widgets/sudoku_grid.dart';
import '../widgets/sudoku_number_pad.dart';
import '../widgets/sudoku_opponent_strip.dart';
import 'sudoku_net.dart';
import 'sudoku_room_config_page.dart';

/// 快照驱动的数独联机房间页（v3 Relay + kSudokuScript）。
class SudokuRoomPage extends StatefulWidget {
  final RoomHandle handle;
  const SudokuRoomPage({super.key, required this.handle});
  @override
  State<SudokuRoomPage> createState() => _SudokuRoomPageState();
}

class _SudokuRoomPageState extends State<SudokuRoomPage> {
  StreamSubscription<Snapshot>? _snapSub;
  Timer? _elapsedTimer;

  Snapshot? _snap;
  SudokuBoard? _board;
  int? _selectedR;
  int? _selectedC;
  int _errors = 0;
  DateTime? _startedAt;
  String _difficulty = 'medium';
  int _elapsedMs = 0;

  String get _deviceId => widget.handle.transport.deviceId;

  bool get _isHost {
    final hid = _snap?.context['host_id']?.toString();
    return hid != null && hid.isNotEmpty && hid == _deviceId;
  }

  bool get _hasGuest {
    final gid = _snap?.context['guest_id']?.toString();
    return gid != null && gid.isNotEmpty;
  }

  bool get _isPlaying => _snap?.state == 'playing';

  @override
  void initState() {
    super.initState();
    final latest = widget.handle.latest;
    if (latest != null) _onSnapshot(latest);
    _snapSub = widget.handle.snapshots.listen(_onSnapshot);
  }

  @override
  void dispose() {
    _snapSub?.cancel();
    _elapsedTimer?.cancel();
    super.dispose();
  }

  void _onSnapshot(Snapshot s) {
    if (!mounted) return;
    setState(() {
      _snap = s;
      final ctx = s.context;
      final d = ctx['difficulty']?.toString();
      if (d != null && d.isNotEmpty) _difficulty = d;
      if (s.state == 'playing' && _startedAt == null) {
        _startedAt = DateTime.now();
        _errors = 0;
        _startElapsedTimer();
      }
      if (_board == null && ctx['puzzle'] is List && ctx['solution'] is List) {
        _board = SudokuBoard.fromPuzzle(SudokuPuzzle(
          puzzle: (ctx['puzzle'] as List).cast<int>(),
          solution: (ctx['solution'] as List).cast<int>(),
          seed: (ctx['seed'] as int?) ?? 0,
          difficulty: ctx['difficulty']?.toString() ?? 'medium',
        ));
      }
    });
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted || _startedAt == null) return;
      setState(() {
        _elapsedMs = DateTime.now().difference(_startedAt!).inMilliseconds;
      });
    });
  }

  List<List<int?>> _boardToGrid(SudokuBoard board) =>
      board.cells.map((row) => row.map((c) => c.value).toList()).toList();

  /// Host 本地生成题目 → send SET_PUZZLE。
  Future<void> _hostGenerateAndSendPuzzle(String difficulty) async {
    if (!_isHost) return;
    final puzzle = SudokuGenerator.generate(
      difficulty: difficulty,
      seed: DateTime.now().microsecondsSinceEpoch,
    );
    setState(() => _difficulty = difficulty);
    try {
      await SudokuNet.sendSetPuzzle(
        widget.handle,
        puzzle: puzzle.puzzle,
        solution: puzzle.solution,
        seed: puzzle.seed,
        difficulty: difficulty,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成题目失败: $e')),
      );
    }
  }

  /// Host 推送 START，前提：guest 已加入 + puzzle 已生成。
  Future<void> _onStart() async {
    if (!_isHost) return;
    try {
      await SudokuNet.sendStart(widget.handle);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('开始对局失败: $e')),
      );
    }
  }

  /// Lua on_join 存的是 true（占位），真实别名走 fallback —— 永远不显示 "true"。
  String _playerName(Map players, String? id, String fallback) {
    if (id == null) return fallback;
    final raw = players[id];
    return raw is String ? raw : fallback;
  }

  void _onNumber(int n) {
    final board = _board;
    final r = _selectedR;
    final c = _selectedC;
    if (board == null || r == null || c == null || !_isPlaying) return;
    final cell = board.cells[r][c];
    if (cell.isInitial) return;
    final wasError = cell.isError;
    board.setValue(r, c, n, isValidMove: (rr, cc, vv) =>
        SudokuValidator.isValidMove(_boardToGrid(board), rr, cc, vv));
    if (!wasError && board.cells[r][c].isError) _errors++;
    if (mounted) setState(() {});
  }

  void _onClear() {
    final board = _board;
    final r = _selectedR;
    final c = _selectedC;
    if (board == null || r == null || c == null) return;
    if (board.cells[r][c].isInitial) return;
    board.setValue(r, c, null, isValidMove: (_, _, _) => true);
    if (mounted) setState(() {});
  }

  Future<void> _onSubmit() async {
    final board = _board;
    if (board == null || !_isPlaying) return;
    if (!board.isComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('棋盘未完成，无法提交')),
      );
      return;
    }
    final values = <int>[
      for (final row in board.cells) for (final cell in row) cell.value ?? 0,
    ];
    final elapsed = _startedAt == null
        ? 0
        : DateTime.now().difference(_startedAt!).inMilliseconds;
    try {
      await SudokuNet.sendSubmit(
        widget.handle, values: values, elapsedMs: elapsed, errors: _errors);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('提交失败: $e')),
      );
    }
  }

  void _onCellTap(int r, int c) {
    final board = _board;
    if (board == null || board.cells[r][c].isInitial) return;
    setState(() {
      final same = _selectedR == r && _selectedC == c;
      _selectedR = same ? null : r;
      _selectedC = same ? null : c;
    });
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snap;
    if (snap == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('数独房间')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final Widget body;
    final state = snap.state;
    if (state == 'lobby' || state == 'ready') {
      body = _buildLobbyReady();
    } else if (state == 'playing') {
      body = _buildPlaying();
    } else {
      body = _buildEnded();
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('房间 ${snap.roomCode}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: '返回',
        ),
      ),
      body: body,
    );
  }

  Widget _buildLobbyReady() {
    final snap = _snap!;
    final colors = context.colors;
    final puzzleReady = snap.context['puzzle'] is List;
    final canStart = _isHost && _hasGuest && puzzleReady;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _hasGuest ? '准备开始' : '等待对手加入',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '房间号 ${snap.roomCode}',
                style: TextStyle(color: colors.textMuted, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (!_hasGuest)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    _isHost ? '把房间号发给朋友吧' : '等待 host 准备…',
                    style: TextStyle(color: colors.textMuted),
                    textAlign: TextAlign.center,
                  ),
                )
              else ...[
                SudokuRoomConfigPanel(
                  editable: _isHost,
                  difficulty: _difficulty,
                  puzzleReady: puzzleReady,
                  onDifficultyChanged:
                      _isHost ? (d) => _hostGenerateAndSendPuzzle(d) : null,
                  onGenerate: _isHost
                      ? () => _hostGenerateAndSendPuzzle(_difficulty)
                      : null,
                ),
                if (_isHost) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: canStart ? _onStart : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('开始对局'),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaying() {
    final board = _board;
    if (board == null) return const Center(child: CircularProgressIndicator());
    final snap = _snap!;
    final players = (snap.context['players'] as Map?) ?? const {};
    final guestId = snap.context['guest_id']?.toString();
    final myName = _playerName(players, _deviceId, '我');
    final guestName = _playerName(players, guestId, 'Guest');
    final oppElapsedMs = guestId == null
        ? null
        : (snap.context['finished_at_ms']?[guestId] as int?) ?? _elapsedMs;
    final selfInfo = SudokuPlayerInfo(
      name: myName,
      filledCount: board.filledCount,
      errorCount: _errors,
      isComplete: board.isComplete,
      elapsed: Duration(milliseconds: _elapsedMs),
    );
    final oppInfo = SudokuPlayerInfo(
      name: guestName,
      filledCount: (snap.context['guest_filled'] as int?) ?? 0,
      errorCount: (snap.context['error_count']?[guestId ?? ''] as int?) ?? 0,
      isComplete: guestId != null &&
          (snap.context['finished_at_ms']?[guestId] != null),
      elapsed: oppElapsedMs == null ? null : Duration(milliseconds: oppElapsedMs),
    );
    return Column(
      children: [
        SudokuOpponentStrip(self: selfInfo, opponent: oppInfo),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: SudokuGrid(
                board: board,
                selectedRow: _selectedR,
                selectedCol: _selectedC,
                onCellTap: _onCellTap,
              ),
            ),
          ),
        ),
        SudokuNumberPad(
          onNumber: _onNumber,
          onClear: _onClear,
          onSubmit: _onSubmit,
        ),
      ],
    );
  }

  Widget _buildEnded() {
    final colors = context.colors;
    final snap = _snap!;
    final winnerId = snap.context['winner_id']?.toString();
    final iAmWinner = winnerId != null && winnerId == _deviceId;
    final players = (snap.context['players'] as Map?) ?? const {};
    final winnerName = _playerName(players, winnerId, '未知');
    final finishedMs = winnerId != null
        ? (snap.context['finished_at_ms']?[winnerId] as int?)
        : null;
    final seconds = (finishedMs ?? 0) ~/ 1000;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              iAmWinner ? '🏆 你赢了！' : (winnerId == null ? '对局结束' : '对手先到终点'),
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              winnerId == null ? '' : '赢家：$winnerName · ${seconds}s',
              style: TextStyle(color: colors.textMuted, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.home_outlined),
              label: const Text('返回大厅'),
            ),
          ],
        ),
      ),
    );
  }
}
