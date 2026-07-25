// lib/lab/demos/surround_game_lua/widgets.dart
// 围追堵截 Lua 版 — UI 组件：SetupPage / JoinPage / OnlineGamePage

import 'dart:async';

import 'package:flutter/material.dart';

import 'constants.dart';
import 'engine.dart' show SgRoom, SgMirror, QuoridorEngine, GameState, MoveRecord,
    GameStatus, Snapshot, RoomHandle, RelayV3Transport, kSurroundGameScript;
import 'package:xiaodouzi_fr/core/surround_game/board_theme.dart';
import 'package:xiaodouzi_fr/core/surround_game/surround_game_constants.dart';
import 'package:xiaodouzi_fr/core/surround_game/widgets/chess_board.dart';
import 'package:xiaodouzi_fr/core/surround_game/widgets/chess_player.dart';
import 'package:xiaodouzi_fr/core/surround_game/widgets/chess_wall.dart';
import 'package:xiaodouzi_fr/core/surround_game/widgets/player_prompt.dart';
import 'package:xiaodouzi_fr/core/surround_game/widgets/wall_prompt.dart';
import 'package:xiaodouzi_fr/core/surround_game/widgets/touch_view.dart';
import 'package:xiaodouzi_fr/core/surround_game/widgets/touch_controller.dart';
import 'package:xiaodouzi_fr/core/surround_game/widgets/player_panel.dart';
import 'package:xiaodouzi_fr/core/surround_game/widgets/confirm_actions.dart';

// ══════════════════════════════════════════════════════════════
// Setup Page（建房）
// ══════════════════════════════════════════════════════════════

class SetupPage extends StatefulWidget {
  const SetupPage({super.key, required this.onCreated});
  final void Function(RoomHandle) onCreated;
  @override State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _aliasCtrl = TextEditingController(text: '红方');
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    SgAliasPrefs.load().then((v) {
      if (mounted && v.isNotEmpty) setState(() => _aliasCtrl.text = v);
    });
  }

  @override
  void dispose() { _aliasCtrl.dispose(); super.dispose(); }

  Future<void> _create() async {
    setState(() { _busy = true; _error = null; });
    try {
      final t = RelayV3Transport(
        relayUrl: kSgRelayUrl,
        alias: _aliasCtrl.text.trim(),
        deviceId: 'sg-${DateTime.now().microsecondsSinceEpoch}',
      );
      await SgAliasPrefs.save(t.alias);
      final h = await t.createRoom(
        script: kSurroundGameScript,
        initialParams: {'device_id': t.deviceId, 'alias': t.alias},
        maxPlayers: 2,
      );
      if (!mounted) return;
      widget.onCreated(h);
    } catch (e) {
      if (!mounted) return;
      setState(() { _busy = false; _error = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.sports_esports, size: 64, color: Colors.orange),
        const SizedBox(height: 16),
        const Text('建房等对手',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 24),
        TextField(
          controller: _aliasCtrl,
          decoration: InputDecoration(
            labelText: '昵称',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            labelStyle: const TextStyle(color: Colors.white60),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          ),
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 16),
        if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _busy ? null : _create,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.meeting_room),
          label: Text(_busy ? '创建中…' : '创建房间'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
            foregroundColor: Colors.orange,
            side: const BorderSide(color: Colors.orange),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ]),
    ),
  );
}

// ══════════════════════════════════════════════════════════════
// Join Page（加入）— 带房间码输入
// ══════════════════════════════════════════════════════════════

class JoinPage extends StatefulWidget {
  const JoinPage({super.key, required this.onJoined});
  final void Function(RoomHandle) onJoined;
  @override State<JoinPage> createState() => _JoinPageState();
}

class _JoinPageState extends State<JoinPage> {
  final _aliasCtrl = TextEditingController(text: '蓝方');
  final _codeCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    SgAliasPrefs.load().then((v) {
      if (mounted && v.isNotEmpty) setState(() => _aliasCtrl.text = v);
    });
  }

  @override
  void dispose() { _aliasCtrl.dispose(); _codeCtrl.dispose(); super.dispose(); }

  Future<void> _join() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) { setState(() => _error = '房间码为 6 位数字'); return; }
    setState(() { _busy = true; _error = null; });
    try {
      final t = RelayV3Transport(
        relayUrl: kSgRelayUrl,
        alias: _aliasCtrl.text.trim(),
        deviceId: 'sg-${DateTime.now().microsecondsSinceEpoch}',
      );
      await SgAliasPrefs.save(t.alias);
      final h = await t.joinRoom(code: code);
      if (!mounted) return;
      widget.onJoined(h);
    } catch (e) {
      if (!mounted) return;
      setState(() { _busy = false; _error = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.vpn_key_outlined, size: 64, color: Colors.blue),
          const SizedBox(height: 16),
          const Text('加入房间',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 24),
          TextField(
            controller: _aliasCtrl,
            decoration: InputDecoration(
              labelText: '昵称',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              labelStyle: const TextStyle(color: Colors.white60),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            ),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _codeCtrl,
            decoration: InputDecoration(
              labelText: '房间码',
              hintText: '6 位数字',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              labelStyle: TextStyle(color: Colors.white60),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            ),
            style: const TextStyle(color: Colors.white),
            keyboardType: TextInputType.number, maxLength: 6,
          ),
          if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _busy ? null : _join,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.login),
            label: Text(_busy ? '加入中…' : '加入'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              foregroundColor: Colors.blue,
              side: const BorderSide(color: Colors.blue),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ]),
      ),
    ),
  );
}

// ══════════════════════════════════════════════════════════════
// Online Game Page（玩游戏）
// ══════════════════════════════════════════════════════════════

class OnlineGamePage extends StatefulWidget {
  const OnlineGamePage({
    super.key,
    required this.handle,
    required this.isHostSide,
    required this.onLeave,
  });
  final RoomHandle handle;
  final bool isHostSide;
  final Future<void> Function() onLeave;

  @override State<OnlineGamePage> createState() => _OnlineGamePageState();
}

class _OnlineGamePageState extends State<OnlineGamePage> {
  StreamSubscription<Snapshot>? _sub;
  Snapshot? _snap;
  GameState _gs = QuoridorEngine.initialize();
  final _touchCtrl = TouchController();
  late final SgRoom _room;
  late final SgMirror _mirror;

  SgLobbyPhase get _phase {
    final s = _snap?.state;
    if (s == null) return SgLobbyPhase.entering;
    if (s == 'lobby') return SgLobbyPhase.waitingAck;
    if (s == 'ready') return SgLobbyPhase.waitingDeal;
    if (s == 'playing') return SgLobbyPhase.playing;
    return SgLobbyPhase.ended;
  }

  bool get _myTurn => SgRoom.isMyTurn(_snap, _gs, _room.deviceId);

  @override
  void initState() {
    super.initState();
    _room = SgRoom(widget.handle);
    _mirror = SgMirror(isHostSide: widget.isHostSide);
    _snap = widget.handle.latest;
    _rebuildGs(widget.handle.latest);
    _sub = widget.handle.snapshots.listen((s) {
      if (!mounted) return;
      setState(() { _snap = s; _rebuildGs(s); });
    });
  }

  void _rebuildGs(Snapshot? s) {
    final snap = s ?? _snap ?? widget.handle.latest;
    _gs = SgRoom.rebuildGameState(snap);
  }

  @override
  void dispose() { _sub?.cancel(); super.dispose(); }

  // ── 网络动作 ──
  Future<void> _ack() async { try { await _room.ack(); } catch (_) {} }
  Future<void> _deal() async { try { await _room.deal(); _touchCtrl.reset(); } catch (_) {} }

  // ── 触摸回调 ──
  void _onPointerDown(Offset pos, double cs, double dist) {
    if (!_myTurn) return;
    final gs = _gs;
    final currentId = gs.currentPlayerIsTop ? gs.topPlayerId : gs.bottomPlayerId;
    final remaining = SurroundGameConstants.wallCountPerPlayer -
        (gs.currentPlayerIsTop ? gs.topWallsPlaced : gs.bottomWallsPlaced);
    _touchCtrl.handleTouchBegan(pos, cs, dist,
      isRunning: gs.status == GameStatus.running,
      currentPlayerId: currentId,
      canPlaceWall: remaining > 0,
      validateWall: (wx, wy, o) => _mirror.validateWall(gs, wx, wy, o),
    );
    setState(() {});
  }

  void _onPointerMove(Offset pos, double cs, double dist) {
    if (!_myTurn) return;
    _touchCtrl.handleTouchMoved(pos, cs, dist,
      validateWall: (wx, wy, o) => _mirror.validateWall(_gs, wx, wy, o),
    );
    setState(() {});
  }

  void _onPointerUp(Offset pos, double cs, double dist) {
    if (!_myTurn) return;
    _touchCtrl.handleTouchEnded(pos, cs, dist,
      isTopTurn: _gs.currentPlayerIsTop,
      validMoves: _gs.validMoves,
      validateWall: (wx, wy, o) => _mirror.validateWall(_gs, wx, wy, o),
    );
    setState(() {});
  }

  void _onPointerCancel() { _touchCtrl.handleTouchCancelled(); setState(() {}); }

  void _onConfirm() {
    final toc = _touchCtrl;
    if (toc.phase != TouchPhase.confirming) return;
    if (toc.pendingWall != null) {
      _room.move(MoveRecord.wall(
        x: toc.pendingWall!.x, y: _mirror.mirrorY(toc.pendingWall!.y),
        orientation: toc.pendingWall!.o,
        isTopPlayer: _gs.currentPlayerIsTop,
      ));
    } else if (toc.pendingTargetCellId != null) {
      final ty = toc.pendingTargetCellId! ~/ 9;
      final tx = toc.pendingTargetCellId! % 9;
      _room.move(MoveRecord.move(
        cellId: _mirror.canonicalCellId(tx, ty),
        isTopPlayer: _gs.currentPlayerIsTop,
      ));
    }
    toc.reset();
    setState(() {});
  }

  Future<void> _reset() async {
    _touchCtrl.reset();
    await _room.reset();
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final theme = BoardTheme.of(context);
    final phase = _phase;
    if (phase == SgLobbyPhase.entering || phase == SgLobbyPhase.waitingAck) return _buildLobby(theme);
    if (phase == SgLobbyPhase.waitingDeal) return _buildReadyWait(theme);
    return _buildGame(theme);
  }

  Widget _buildLobby(BoardThemeData theme) {
    final code = _snap?.roomCode ?? '------';
    final players = SgRoom.players(_snap);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: Text(code,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold,
                    letterSpacing: 6, color: Colors.orange)),
          ),
          const SizedBox(height: 16),
          Text('等待对手加入…', style: TextStyle(color: Colors.white60, fontSize: 13)),
          const SizedBox(height: 24),
          ...players.entries.map((e) => ListTile(
            leading: CircleAvatar(
              backgroundColor: e.key == _room.deviceId ? Colors.green : Colors.grey,
              child: Text(e.value[0].toUpperCase()),
            ),
            title: Text('${e.value}${e.key == _room.deviceId ? " (我)" : ""}',
                style: const TextStyle(color: Colors.white)),
          )),
          if (players.length >= 2) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _ack,
              icon: const Icon(Icons.check_circle_outlined),
              label: const Text('准备好了'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.green.shade400,
                side: BorderSide(color: Colors.green.shade400),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                minimumSize: const Size(200, 48),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _buildReadyWait(BoardThemeData theme) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.hourglass_top, size: 48, color: Colors.orange),
        const SizedBox(height: 16),
        const Text('双方已准备好', style: TextStyle(fontSize: 18, color: Colors.white)),
        const SizedBox(height: 24),
        if (_room.isHost)
          OutlinedButton.icon(
            onPressed: _deal,
            icon: const Icon(Icons.play_arrow),
            label: const Text('开始游戏'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.green,
              side: const BorderSide(color: Colors.green),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              minimumSize: const Size(200, 48),
            ),
          )
        else
          Text('等待房主开始…', style: TextStyle(color: Colors.white60)),
      ]),
    );
  }

  // ── 游戏棋盘 ──

  Widget _buildGame(BoardThemeData theme) {
    final gs = _gs;
    final isRunning = gs.status == GameStatus.running;
    return Stack(children: [
      Column(children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: Center(child: _buildPlayerPanel(theme, rotated: true, isTop: true)),
        ),
        Expanded(child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final cs = w / 11;
            final dist = cs * 1.25;
            return Center(child: SizedBox(
              width: w, height: w,
              child: Stack(clipBehavior: Clip.none, children: [
                ChessBoard(cellSize: cs, theme: theme),
                _boardOverlay(gs, cs, theme, dist),
                if (isRunning && _myTurn)
                  TouchView(
                    cellSize: cs, distance: dist,
                    onPointerDown: (p, c, d) => _onPointerDown(p, c, d),
                    onPointerMove: (p, c, d) => _onPointerMove(p, c, d),
                    onPointerUp: (p, c, d) => _onPointerUp(p, c, d),
                    onPointerCancel: _onPointerCancel,
                  ),
                ConfirmActions(
                  phase: _touchCtrl.phase,
                  pendingTargetCellId: _touchCtrl.pendingTargetCellId,
                  pendingWall: _touchCtrl.pendingWall,
                  isTopTurn: gs.currentPlayerIsTop,
                  cellSize: cs, boardSize: w, theme: theme,
                  onConfirm: _onConfirm,
                  onCancel: () { _touchCtrl.cancelAction(); setState(() {}); },
                  onRotate: () {
                    _touchCtrl.rotatePendingWall(
                      validateWall: (wx, wy, o) => _mirror.validateWall(gs, wx, wy, o),
                    ); setState(() {});
                  },
                ),
              ]),
            ));
          },
        )),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 10),
          child: Center(child: _buildPlayerPanel(theme, rotated: false, isTop: false)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (isRunning && _room.isHost)
              _bottomAction(Icons.refresh, '重新开始', theme, _reset),
            const SizedBox(width: 16),
            _bottomAction(Icons.exit_to_app, '退出', theme, widget.onLeave),
          ]),
        ),
      ]),
      if (gs.status != GameStatus.running) _buildOverlay(gs, theme),
    ]);
  }

  Widget _boardOverlay(GameState gs, double cs, BoardThemeData theme, double dist) {
    final toc = _touchCtrl;
    final pendingId = toc.pendingTargetCellId;
    final topId = pendingId != null && gs.currentPlayerIsTop ? pendingId : _mirror.displayCellId(gs.topPlayerId);
    final bottomId = pendingId != null && !gs.currentPlayerIsTop ? pendingId : _mirror.displayCellId(gs.bottomPlayerId);

    return Stack(clipBehavior: Clip.none, children: [
      ChessWall(history: _mirror.displayHistory(gs.history), cellSize: cs, theme: theme),
      PlayerPrompt(validMoves: _mirror.displayValidMoves(gs.validMoves), cellSize: cs, theme: theme, visible: toc.targetCellId != null),
      ChessPlayer(cellId: topId, cellSize: cs, color: theme.piecePlayerA),
      ChessPlayer(cellId: bottomId, cellSize: cs, color: theme.piecePlayerB),
      if (pendingId != null)
        Positioned(
          left: (pendingId % 9) * dist + 1, top: (pendingId ~/ 9) * dist + 1,
          child: Container(
            width: cs - 2, height: cs - 2,
            decoration: BoxDecoration(
              color: theme.validMoveRing.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: theme.validMoveRing.withValues(alpha: 0.7), width: 2),
            ),
          ),
        ),
      WallPrompt(wallData: toc.previewWall ?? toc.pendingWall, cellSize: cs, theme: theme,
          isValid: toc.wallPreviewValid, visible: toc.previewWall != null || toc.pendingWall != null),
    ]);
  }

  Widget _buildPlayerPanel(BoardThemeData theme, {required bool rotated, required bool isTop}) {
    final gs = _gs;
    final isRunning = gs.status == GameStatus.running;
    final active = isRunning && isTop == gs.currentPlayerIsTop;
    final toc = _touchCtrl;
    final steps = gs.history.where((m) => !m.isWall && m.isTopPlayer == isTop).length;
    final walls = isTop ? gs.topWallsPlaced : gs.bottomWallsPlaced;
    return PlayerPanel(
      rotated: rotated, active: active, isTop: isTop,
      mode: toc.mode, phase: toc.phase,
      canPlaceWall: SurroundGameConstants.wallCountPerPlayer - walls > 0,
      playerSteps: steps, remainingWalls: SurroundGameConstants.wallCountPerPlayer - walls,
      canRequestUndo: false,
      onToggleMode: active ? () { _touchCtrl.toggleMode(); setState(() {}); } : null,
      onConfirm: (toc.phase == TouchPhase.confirming && active) ? _onConfirm : null,
      onCancel: (toc.phase == TouchPhase.confirming && active)
          ? () { _touchCtrl.cancelAction(); setState(() {}); } : null,
      onRotate: (toc.phase == TouchPhase.confirming && active)
          ? () { _touchCtrl.rotatePendingWall(validateWall: (wx, wy, o) => _mirror.validateWall(gs, wx, wy, o)); setState(() {}); } : null,
      pendingWall: toc.pendingWall,
    );
  }

  Widget _bottomAction(IconData icon, String label, BoardThemeData theme, VoidCallback? onTap) {
    final color = theme.btnText.withValues(alpha: onTap != null ? 0.6 : 0.25);
    return GestureDetector(
      behavior: HitTestBehavior.opaque, onTap: onTap,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ]),
    );
  }

  Widget _buildOverlay(GameState gs, BoardThemeData theme) {
    final isTopWin = gs.status == GameStatus.topWin;
    final msg = gs.status == GameStatus.draw ? '平局'
        : (isTopWin ? (_room.isHost ? '我方获胜！' : '上方获胜')
            : (_room.isHost ? '对方获胜' : '我方获胜！'));
    final winColor = gs.status == GameStatus.draw ? Colors.orange
        : (isTopWin ? theme.piecePlayerA : theme.piecePlayerB);
    return Container(
      color: Colors.black.withValues(alpha: 0.5),
      child: Center(child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        decoration: BoxDecoration(color: theme.panelBg, borderRadius: BorderRadius.circular(16)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.emoji_events, size: 48, color: winColor),
          const SizedBox(height: 12),
          Text(msg, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: winColor)),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _room.isHost ? _reset : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: winColor, side: BorderSide(color: winColor),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            child: const Text('再来一局'),
          ),
        ]),
      )),
    );
  }
}
