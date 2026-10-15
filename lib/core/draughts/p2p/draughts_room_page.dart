// lib/core/draughts/p2p/draughts_room_page.dart
//
// 国际跳棋对局房页：准备 / 对战 / 终局三态。
//
// ## 流程
//
//   lobby（双方 ACK）→ ready（host DEAL）→ playing → ended（CLAIM_END / RESIGN / DRAW）
//   终局后 host 可 RESET 回 lobby 再来一局。
//
// ## 交互
//
//   点选中己方子 → 高亮该子全部合法落点 → 点落点执行该手。
//   吃子时引擎已做最长吃子裁决，落点即"最终落点"；同落点多条链时取第一条
//   （确定性，且实战中同起终点异路径极少）。
//
// ## 权威归属
//
//   棋谱（c.moves）由服务端权威维护；本页用引擎重放渲染（rebuildBoard）。
//   终局由本页引擎判定后 CLAIM_END 上报（relay 不做跳棋规则推理）。

import 'dart:async';

import 'package:flutter/material.dart';

import '../engine/draughts_engine.dart';
import '../engine/make_move.dart';
import '../engine/pdn_codec.dart';
import '../models/board_state.dart';
import '../models/game_status.dart';
import '../models/move.dart';
import '../models/piece.dart';
import '../widgets/draughts_board.dart';
import 'draughts_room.dart';

class DraughtsRoomPage extends StatefulWidget {
  const DraughtsRoomPage({
    super.key,
    required this.handle,
    required this.onLeave,
  });

  final RoomHandle handle;
  final Future<void> Function() onLeave;

  @override
  State<DraughtsRoomPage> createState() => _DraughtsRoomPageState();
}

class _DraughtsRoomPageState extends State<DraughtsRoomPage> {
  StreamSubscription<Snapshot>? _sub;
  late final DraughtsRoom _room;

  Snapshot? _snap;
  List<DraughtsMoveRecord> _history = const [];
  DraughtsBoardState _board = DraughtsBoardState.initial();

  int? _selected;
  Set<int> _targets = const {};
  Set<int> _lastPath = const {};

  bool _ackedLocally = false;
  bool _endDeclared = false;

  @override
  void initState() {
    super.initState();
    _room = DraughtsRoom(widget.handle);
    _snap = widget.handle.latest;
    _applySnapshot(_snap);
    _sub = widget.handle.snapshots.listen(_onSnapshot);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ── 快照 ──

  void _onSnapshot(Snapshot s) {
    if (!mounted) return;
    final prev = _snap?.state;
    // RESET 合法推进：ended → lobby（房主「再来一局」）。
    // isStateRegression 把任何 ended→非 ended 都当回退，这里显式放行。
    final isResetRematch = prev == 'ended' && s.state == 'lobby';
    if (_snap != null &&
        !isResetRematch &&
        RoomHandle.isStateRegression(prev, s.state)) {
      return; // 服务端快照端点回退 → 忽略
    }
    setState(() => _applySnapshot(s));
    if (_ackedLocally && s.state != 'lobby' && s.state != 'ready') {
      setState(() => _ackedLocally = false);
    }
    if (s.state == 'lobby') _endDeclared = false;
    _maybeDeclareEnd();
  }

  void _applySnapshot(Snapshot? s) {
    _snap = s;
    _history = DraughtsRoom.rebuildHistory(s);
    _board = DraughtsRoom.rebuildBoard(_history, initialFen: DraughtsRoom.initialFen(s));
    _selected = null;
    _targets = const {};
    _lastPath = _history.isEmpty
        ? const {}
        : _pathOfLastMove(_history.last);
  }

  Set<int> _pathOfLastMove(DraughtsMoveRecord rec) {
    // 用"上一手之前的局面"解析 PDN 路径（取 path 的格索引）
    final before = DraughtsRoom.rebuildBoard(
      _history.sublist(0, _history.length - 1),
      initialFen: DraughtsRoom.initialFen(_snap),
    );
    final m = pdnMoveToMove(before, rec.pdn);
    if (m == null) return const {};
    return m.path.toSet();
  }

  // ── 角色 ──

  String get _me => widget.handle.transport.deviceId;
  DraughtsColor get _myColor => DraughtsRoom.myColor(widget.handle, _snap);
  bool get _isHost => _me == DraughtsRoom.hostId(_snap);
  bool get _isPlaying => _snap?.state == 'playing';
  bool get _isMyTurn =>
      _isPlaying && _board.sideToMove == _myColor && !_endDeclared;

  List<DraughtsMove> get _myLegalMoves => _isMyTurn
      ? kDefaultDraughtsEngine.legalMoves(_board)
      : const [];

  // ── 终局上报 ──

  void _maybeDeclareEnd() {
    if (_endDeclared || !_isPlaying) return;
    final keys = DraughtsRoom.rebuildPositionHistory(
      _history,
      initialFen: DraughtsRoom.initialFen(_snap),
    );
    final st = kDefaultDraughtsEngine.status(_board, positionHistory: keys);
    if (!st.isOver) return;
    _endDeclared = true;
    // 只有"刚走完的一方"能声明（= 非当前走子方）
    final claimerIsMe = _board.sideToMove != _myColor;
    if (!claimerIsMe) return;
    _room.declareEnd(_reasonName(st.reason));
  }

  String _reasonName(DraughtsEndReason r) {
    switch (r) {
      case DraughtsEndReason.noPieces:
        return 'noPieces';
      case DraughtsEndReason.noMoves:
        return 'noMoves';
      case DraughtsEndReason.threefoldRepetition:
        return 'threefold';
      case DraughtsEndReason.kingVsKing:
        return 'kingVsKing';
      case DraughtsEndReason.kingMoveLimit:
        return 'kingMoveLimit';
      default:
        return 'noMoves';
    }
  }

  // ── 交互 ──

  void _onTapSquare(int index) {
    if (!_isMyTurn) return;
    final piece = _board.pieceAt(index);

    // 点自己的子 → 选中并显示落点
    if (piece != null && piece.color == _myColor) {
      final mine = _myLegalMoves.where((m) => m.from == index).toList();
      setState(() {
        _selected = index;
        _targets = mine.map((m) => m.to).toSet();
      });
      return;
    }

    // 点落点 → 执行
    if (_selected != null && _targets.contains(index)) {
      final candidates =
          _myLegalMoves.where((m) => m.from == _selected && m.to == index);
      if (candidates.isEmpty) return;
      final move = candidates.first;
      _playMove(move);
      return;
    }

    setState(() {
      _selected = null;
      _targets = const {};
    });
  }

  Future<void> _playMove(DraughtsMove move) async {
    final next = applyMoveSimple(_board, move);
    setState(() {
      _selected = null;
      _targets = const {};
      _lastPath = move.path.toSet();
    });
    await _room.move(move, next);
  }

  // ── 动作 ──

  Future<void> _ack() async {
    setState(() => _ackedLocally = true);
    await _room.ack();
  }

  Future<void> _deal() => _room.deal();
  Future<void> _reset() => _room.reset();

  Future<void> _confirmResign() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('认输'),
        content: const Text('确定要认输吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('认输'),
          ),
        ],
      ),
    );
    if (ok == true) await _room.resign();
  }

  /// 离开房间并 pop 回大厅（对齐 ChessRoomPage._leaveAndPop）。
  Future<void> _leaveAndPop() async {
    final nav = Navigator.of(context);
    await widget.onLeave();
    if (!mounted) return;
    if (nav.canPop()) nav.pop();
  }

  // ── 渲染 ──

  @override
  Widget build(BuildContext context) {
    // 拦截 AppBar 返回 / 系统返回：必须先 leave 再 pop，避免幽灵座位。
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _leaveAndPop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('国际跳棋（联机）'),
          actions: [
            if (_isPlaying)
              IconButton(
                tooltip: '认输',
                icon: const Icon(Icons.flag_outlined),
                onPressed: _confirmResign,
              ),
            IconButton(
              tooltip: '退出',
              icon: const Icon(Icons.logout),
              onPressed: _leaveAndPop,
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              _statusBar(context),
              Expanded(child: _boardArea()),
              _actionBar(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBar(BuildContext context) {
    final players = DraughtsRoom.players(_snap);
    final meName = players[_me] ?? '我';
    final oppId = _isHost ? DraughtsRoom.guestId(_snap) : DraughtsRoom.hostId(_snap);
    final oppName = oppId == null ? '等待加入…' : (players[oppId] ?? '对手');
    final disconnected = DraughtsRoom.disconnectedPlayers(_snap);
    final oppOffline = oppId != null && disconnected[oppId] == true;

    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: scheme.surfaceContainerHighest,
      child: Row(
        children: [
          _colorDot(_myColor),
          const SizedBox(width: 6),
          Text('$meName（我）', style: Theme.of(context).textTheme.bodyMedium),
          const Spacer(),
          if (oppOffline)
            Text('对手已离线',
                style: TextStyle(color: scheme.error, fontSize: 12)),
          const SizedBox(width: 8),
          Text(oppName, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(width: 6),
          _colorDot(draughtsOpposite(_myColor)),
        ],
      ),
    );
  }

  Widget _colorDot(DraughtsColor c) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c == DraughtsColor.white
              ? const Color(0xFFF7F3E8)
              : const Color(0xFF2A2A2E),
          border: Border.all(color: const Color(0xFF8A7B5C)),
        ),
      );

  Widget _boardArea() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: DraughtsBoard(
            state: _board,
            flipped: _myColor == DraughtsColor.black,
            selectedSquare: _selected,
            legalTargets: _targets,
            lastMovePath: _lastPath,
            interactive: _isMyTurn,
            onTapSquare: _onTapSquare,
          ),
        ),
      ),
    );
  }

  Widget _actionBar(BuildContext context) {
    final state = _snap?.state;
    final scheme = Theme.of(context).colorScheme;
    final dt = Theme.of(context).textTheme;

    Widget wrap(Widget child) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: child,
        );

    switch (state) {
      case 'lobby':
      case 'ready':
        final ready = DraughtsRoom.readyMap(_snap);
        final iAmReady = ready[_me] == true || _ackedLocally;
        final allReady = _snap?.state == 'ready';
        return wrap(Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              allReady
                  ? (_isHost ? '双方已准备，开始对局' : '等待房主开始…')
                  : '等待双方准备',
              style: dt.bodyMedium,
            ),
            const SizedBox(height: 12),
            if (!iAmReady)
              FilledButton(
                onPressed: _ack,
                child: const Text('准备好了'),
              )
            else if (_isHost && allReady)
              FilledButton(
                onPressed: _deal,
                child: const Text('开始对局'),
              )
            else
              OutlinedButton(onPressed: null, child: const Text('等待对手…')),
          ],
        ));

      case 'playing':
        final turnText = _isMyTurn ? '轮到你走' : '等待对手…';
        final mustCapture = _isMyTurn &&
            kDefaultDraughtsEngine
                .legalMoves(_board)
                .any((m) => m.isCapture);
        return wrap(Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(turnText, style: dt.titleMedium),
            if (mustCapture)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('有吃子，必须吃（最长吃子）',
                    style: dt.bodySmall?.copyWith(color: scheme.error)),
              ),
          ],
        ));

      case 'ended':
        return wrap(Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_resultText(), style: dt.titleLarge),
            const SizedBox(height: 12),
            if (_isHost)
              FilledButton(onPressed: _reset, child: const Text('再来一局'))
            else
              const Text('等待房主重开…'),
          ],
        ));

      default:
        return wrap(Text('房间状态：$state', style: dt.bodyMedium));
    }
  }

  String _resultText() {
    final status = DraughtsRoom.status(_snap);
    final winner = DraughtsRoom.winner(_snap);
    final reason = DraughtsRoom.endReason(_snap);
    if (status == 'draw') {
      return switch (reason) {
        'kingVsKing' => '和棋（王对王）',
        'threefold' => '和棋（三次重复）',
        'agreement' => '和棋（双方同意）',
        _ => '和棋',
      };
    }
    if (status == 'resigned') {
      return winner == _me ? '对方认输，你赢了' : '你认输了';
    }
    if (status == 'win') {
      if (winner == _me) return '你赢了！';
      if (winner == null) return '对局结束';
      return '对手获胜';
    }
    if (status == 'ended') return '对局结束';
    return '对局结束';
  }
}
