// lib/lab/demos/surround_game_lua_demo.dart
// 围追堵截（Quoridor）互联网双人对战 — v3 Lua 状态机版
//
// 流程：
//   房主创建房间 → 玩家输入码加入 → 双方 ACK → 房主点开始 → playing → 交替 MOVE
//
// 镜像策略：
//   - 服务端存规范坐标（host=top=y0, guest=bottom=y8）
//   - host 端 y 方向翻转后渲染（host 自身在下方）
//   - guest 端直接渲染（guest 自身在下方）
//   - 触摸坐标也相应翻转

import 'dart:async';

import 'package:flutter/material.dart';
import '../lab_container.dart';
import 'package:xiaodouzi_fr/core/net_p2p/scripts/lua_scripts.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart';
import 'package:xiaodouzi_fr/core/surround_game/engine/game_engine.dart';
import 'package:xiaodouzi_fr/core/surround_game/models/game_state.dart';
import 'package:xiaodouzi_fr/core/surround_game/surround_game_constants.dart';
import 'package:xiaodouzi_fr/core/surround_game/board_theme.dart';
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
// Demo 注册
// ══════════════════════════════════════════════════════════════

class SurroundGameLuaDemo extends DemoPage {
  SurroundGameLuaDemo();
  @override String get title => '围追堵截（Lua）';
  @override String get slug => 'surround-game-lua';
  @override String get description => 'Quoridor 互联网双人对战 · Lua 服务端权威棋谱';
  @override bool get preferFullScreen => true;
  @override Widget buildPage(BuildContext context) => const _SurroundGameLuaPage();
}

void registerSurroundGameLuaDemo() => demoRegistry.register(SurroundGameLuaDemo());

// ══════════════════════════════════════════════════════════════
// 主页面
// ══════════════════════════════════════════════════════════════

class _SurroundGameLuaPage extends StatefulWidget {
  const _SurroundGameLuaPage();
  @override State<_SurroundGameLuaPage> createState() => _SurroundGameLuaPageState();
}

class _SurroundGameLuaPageState extends State<_SurroundGameLuaPage> {
  RoomHandle? _handle;
  final bool _isMaster = true;
  bool _isHostSide = false; // true=host/top, false=guest/bottom

  @override
  void dispose() {
    _handle?.dispose();
    super.dispose();
  }

  void _onRoomCreated(RoomHandle h) =>
      setState(() { _handle = h; _isHostSide = true; });
  void _onRoomJoined(RoomHandle h) =>
      setState(() { _handle = h; _isHostSide = false; });
  Future<void> _disconnect() async {
    final h = _handle;
    setState(() => _handle = null);
    if (h != null) await h.leave();
  }

  @override
  Widget build(BuildContext context) {
    if (_handle != null) {
      return Scaffold(
        backgroundColor: Colors.grey.shade900,
        appBar: AppBar(
          title: const Text('围追堵截'),
          backgroundColor: Colors.grey.shade900,
          foregroundColor: Colors.white70,
        ),
        body: _OnlineGamePage(
          handle: _handle!,
          isHostSide: _isHostSide,
          onLeave: _disconnect,
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.grey.shade900,
      appBar: AppBar(
        title: const Text('围追堵截'),
        backgroundColor: Colors.grey.shade900,
        foregroundColor: Colors.white70,
      ),
      body: _isMaster
          ? _SetupPage(onCreated: _onRoomCreated)
          : _JoinPage(onJoined: _onRoomJoined),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 建房 + 信息展示
// ══════════════════════════════════════════════════════════════

class _SetupPage extends StatefulWidget {
  const _SetupPage({required this.onCreated});
  final void Function(RoomHandle) onCreated;
  @override State<_SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<_SetupPage> {
  final _aliasCtrl = TextEditingController(text: '红方');
  bool _busy = false;
  String? _error;

  Future<void> _create() async {
    setState(() { _busy = true; _error = null; });
    try {
      final t = RelayV3Transport(
        relayUrl: 'http://47.110.80.47:8988',
        alias: _aliasCtrl.text.trim(),
        deviceId: 'sg-${DateTime.now().microsecondsSinceEpoch}',
      );
      final h = await t.createRoom(
        script: kSurroundGameScript,
        initialParams: {
          'device_id': t.deviceId,
          'alias': t.alias,
        },
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
  Widget build(BuildContext context) {
    return Center(
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
              enabledBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
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
}

// ══════════════════════════════════════════════════════════════
// 加入
// ══════════════════════════════════════════════════════════════

class _JoinPage extends StatefulWidget {
  const _JoinPage({required this.onJoined});
  final void Function(RoomHandle) onJoined;
  @override State<_JoinPage> createState() => _JoinPageState();
}

class _JoinPageState extends State<_JoinPage> {
  final _aliasCtrl = TextEditingController(text: '蓝方');
  final _codeCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _join() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) { setState(() => _error = '6 位房间码'); return; }
    setState(() { _busy = true; _error = null; });
    try {
      final t = RelayV3Transport(
        relayUrl: 'http://47.110.80.47:8988',
        alias: _aliasCtrl.text.trim(),
        deviceId: 'sg-${DateTime.now().microsecondsSinceEpoch}',
      );
      final h = await t.joinRoom(code: code);
      if (!mounted) return;
      widget.onJoined(h);
    } catch (e) {
      if (!mounted) return;
      setState(() { _busy = false; _error = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
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
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 在线游戏页面
// ══════════════════════════════════════════════════════════════

enum _LobbyPhase { entering, waitingAck, waitingDeal, playing, ended }

class _OnlineGamePage extends StatefulWidget {
  const _OnlineGamePage({required this.handle, required this.isHostSide, required this.onLeave});
  final RoomHandle handle;
  final bool isHostSide;
  final Future<void> Function() onLeave;

  @override State<_OnlineGamePage> createState() => _OnlineGamePageState();
}

class _OnlineGamePageState extends State<_OnlineGamePage> {
  StreamSubscription<Snapshot>? _sub;
  Snapshot? _snap;
  final _touchCtrl = TouchController();
  bool _touchInitialized = false;

  /// 本地重建成的最新 GameState
  GameState _gameState = QuoridorEngine.initialize();

  String get _myId => widget.handle.transport.deviceId;
  bool get _isHost => _myId.startsWith('sg-');

  _LobbyPhase get _phase {
    final s = _snap?.state;
    if (s == null) return _LobbyPhase.entering;
    if (s == 'lobby') return _LobbyPhase.waitingAck;
    if (s == 'ready') return _LobbyPhase.waitingDeal;
    if (s == 'playing') return _LobbyPhase.playing;
    return _LobbyPhase.ended;
  }

  /// 是否由本地玩家执行走棋
  bool get _myTurn {
    if (_phase != _LobbyPhase.playing) return false;
    final hostId = _snap?.context['host_id']?.toString();
    final history = _gameState.history;
    if (history.isEmpty) return _myId == hostId; // host 先手
    final last = history.last;
    // 如果上一步是 host 走的，那轮到 guest
    return last.isTopPlayer ? _myId != hostId : _myId == hostId;
  }

  @override
  void initState() {
    super.initState();
    _snap = widget.handle.latest;
    _sub = widget.handle.snapshots.listen(_onSnapshot);
  }

  void _onSnapshot(Snapshot s) {
    if (!mounted) return;
    setState(() {
      _snap = s;
      _rebuildGameState(s);
    });
  }

  /// 从 history 重建 GameState
  void _rebuildGameState(Snapshot s) {
    final raw = s.context['history'];
    if (raw is! List || raw.isEmpty) {
      _gameState = QuoridorEngine.initialize();
      return;
    }
    final records = raw
        .map((e) => MoveRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    _gameState = QuoridorEngine.replayHistory(records);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ── 动作 ──

  Future<void> _ack() async {
    try { await widget.handle.applyAction(type: 'ACK', params: const {}); }
    catch (_) {}
  }

  Future<void> _deal() async {
    try {
      await widget.handle.applyAction(type: 'DEAL', params: const {});
      _touchCtrl.reset();
      _touchInitialized = false;
    } catch (_) {}
  }

  Future<void> _sendMove(MoveRecord record) async {
    try {
      await widget.handle.applyAction(
        type: 'MOVE',
        params: {'move': record.toJson()},
      );
    } catch (_) {}
  }

  // ── 触摸回调（带镜像） ──

  bool get _needMirror => widget.isHostSide;

  /// y 翻转：规范坐标 ↔ 镜像坐标
  int _mirrorY(int y) => _needMirror ? 8 - y : y;

  /// 从触摸坐标 → 规范 cellId
  int _canonicalCellId(int tx, int ty) {
    final y = _mirrorY(ty);
    return y * 9 + tx;
  }

  void _onPointerDown(Offset pos, double cs, double dist) {
    if (!_myTurn) return;
    if (!_touchInitialized) { _touchInitialized = true; }

    final gs = _gameState;
    final currentId = gs.currentPlayerIsTop ? gs.topPlayerId : gs.bottomPlayerId;
    final wallsPlaced = gs.currentPlayerIsTop ? gs.topWallsPlaced : gs.bottomWallsPlaced;
    final remaining = SurroundGameConstants.wallCountPerPlayer - wallsPlaced;

    _touchCtrl.handleTouchBegan(
      pos, cs, dist,
      isRunning: gs.status == GameStatus.running,
      currentPlayerId: currentId,
      canPlaceWall: remaining > 0,
      validateWall: (wx, wy, o) => QuoridorEngine.isWallPlacementValid(
        gs.wallGrid, gs.adjacency, gs.topPlayerId, gs.bottomPlayerId,
        wx, _mirrorY(wy), o,
      ),
    );
    setState(() {});
  }

  void _onPointerMove(Offset pos, double cs, double dist) {
    if (!_myTurn) return;
    _touchCtrl.handleTouchMoved(pos, cs, dist,
      validateWall: (wx, wy, o) => QuoridorEngine.isWallPlacementValid(
        _gameState.wallGrid, _gameState.adjacency,
        _gameState.topPlayerId, _gameState.bottomPlayerId,
        wx, _mirrorY(wy), o,
      ),
    );
    setState(() {});
  }

  void _onPointerUp(Offset pos, double cs, double dist) {
    if (!_myTurn) return;
    _touchCtrl.handleTouchEnded(pos, cs, dist,
      isTopTurn: _gameState.currentPlayerIsTop,
      validMoves: _gameState.validMoves,
      validateWall: (wx, wy, o) => QuoridorEngine.isWallPlacementValid(
        _gameState.wallGrid, _gameState.adjacency,
        _gameState.topPlayerId, _gameState.bottomPlayerId,
        wx, _mirrorY(wy), o,
      ),
    );
    setState(() {});
  }

  void _onPointerCancel() {
    _touchCtrl.handleTouchCancelled();
    setState(() {});
  }

  void _onConfirm() {
    final toc = _touchCtrl;
    if (toc.phase != TouchPhase.confirming) return;

    if (toc.pendingWall != null) {
      // 放墙
      final rawX = toc.pendingWall!.x;
      final rawY = toc.pendingWall!.y;
      final o = toc.pendingWall!.o;
      final canonicalY = _mirrorY(rawY);
      final record = MoveRecord.wall(x: rawX, y: canonicalY, orientation: o,
          isTopPlayer: _gameState.currentPlayerIsTop);
      _sendMove(record);
    } else if (toc.pendingTargetCellId != null) {
      // 走棋
      final ty = toc.pendingTargetCellId! ~/ 9;
      final tx = toc.pendingTargetCellId! % 9;
      final canonicalCellId = _canonicalCellId(tx, ty);
      final record = MoveRecord.move(cellId: canonicalCellId,
          isTopPlayer: _gameState.currentPlayerIsTop);
      _sendMove(record);
    }
    toc.reset();
    setState(() {});
  }

  // ── 棋盘渲染中的镜像 ──

  /// 镜像版的 ChessPlayer cellId
  int _displayCellId(int canonicalId) {
    if (!_needMirror) return canonicalId;
    final y = canonicalId ~/ 9;
    final x = canonicalId % 9;
    return _mirrorY(y) * 9 + x;
  }

  /// 镜像版的 validMoves
  Set<int> _displayValidMoves() {
    if (!_needMirror) return _gameState.validMoves;
    return _gameState.validMoves.map((c) {
      final y = c ~/ 9;
      final x = c % 9;
      return _mirrorY(y) * 9 + x;
    }).toSet();
  }

  /// 镜像版的 history（所有坐标翻转）
  List<MoveRecord> get _displayHistory {
    if (!_needMirror) return _gameState.history;
    return _gameState.history.map((m) {
      if (m.isWall) {
        return MoveRecord.wall(x: m.x, y: _mirrorY(m.y), orientation: m.orientation!,
            isTopPlayer: m.isTopPlayer);
      }
      final cy = m.y;
      return MoveRecord.move(cellId: _mirrorY(cy) * 9 + m.x,
          isTopPlayer: m.isTopPlayer);
    }).toList();
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final theme = BoardTheme.of(context);
    final phase = _phase;

    if (phase == _LobbyPhase.entering || phase == _LobbyPhase.waitingAck) {
      return _buildLobby(theme);
    }
    if (phase == _LobbyPhase.waitingDeal) {
      return _buildReadyWait(theme);
    }
    return _buildGame(theme);
  }

  Widget _buildLobby(BoardThemeData theme) {
    final code = _snap?.roomCode ?? '------';
    final players = _extractPlayers();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.tag, size: 32, color: Colors.white60),
          const SizedBox(height: 8),
          Text(code,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold,
                  letterSpacing: 6, color: Colors.white)),
          const SizedBox(height: 16),
          Text('等待对手加入…', style: TextStyle(color: Colors.white60)),
          const SizedBox(height: 24),
          ...players.entries.map((e) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: e.key == _myId ? Colors.green : Colors.grey,
                  child: Text(e.value[0].toUpperCase()),
                ),
                title: Text('${e.value}${e.key == _myId ? " (我)" : ""}',
                    style: const TextStyle(color: Colors.white)),
              )),
          if (players.length >= 2) ...[
            const SizedBox(height: 24),
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
        if (_isHost)
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

  Widget _buildGame(BoardThemeData theme) {
    final gs = _gameState;
    final isRunning = gs.status == GameStatus.running;
    final isFinished = !isRunning;
    final phase = _phase;

    return Stack(
      children: [
        Column(
          children: [
            // 上方面板
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Center(child: _buildPlayerPanel(theme, rotated: true, isTop: true)),
            ),
            // 棋盘
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final cellSize = w / 11;
                  final distance = cellSize * 1.25;
                  final boardSize = w;
                  return Center(
                    child: SizedBox(
                      width: boardSize,
                      height: boardSize,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ChessBoard(cellSize: cellSize, theme: theme),
                          // 墙壁 + 棋子 + 提示
                          _buildBoardOverlay(gs, cellSize, theme, distance),
                          // 触摸层
                          if (isRunning && _myTurn)
                            TouchView(
                              cellSize: cellSize,
                              distance: distance,
                              onPointerDown: (p, cs, d) => _onPointerDown(p, cs, d),
                              onPointerMove: (p, cs, d) => _onPointerMove(p, cs, d),
                              onPointerUp: (p, cs, d) => _onPointerUp(p, cs, d),
                              onPointerCancel: _onPointerCancel,
                            ),
                          // 确认按钮
                          ConfirmActions(
                            phase: _touchCtrl.phase,
                            pendingTargetCellId: _touchCtrl.pendingTargetCellId,
                            pendingWall: _touchCtrl.pendingWall,
                            isTopTurn: gs.currentPlayerIsTop,
                            cellSize: cellSize,
                            boardSize: boardSize,
                            theme: theme,
                            onConfirm: _onConfirm,
                            onCancel: () { _touchCtrl.cancelAction(); setState(() {}); },
                            onRotate: () {
                              _touchCtrl.rotatePendingWall(
                                validateWall: (wx, wy, o) => QuoridorEngine.isWallPlacementValid(
                                  gs.wallGrid, gs.adjacency, gs.topPlayerId, gs.bottomPlayerId,
                                  wx, _mirrorY(wy), o,
                                ),
                              );
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            // 下方面板
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 10),
              child: Center(child: _buildPlayerPanel(theme, rotated: false, isTop: false)),
            ),
            // 底部按钮
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (isRunning && _isHost)
                  _bottomAction(Icons.refresh, '重新开始', theme, _reset),
                const SizedBox(width: 16),
                _bottomAction(Icons.exit_to_app, '退出', theme, widget.onLeave),
              ]),
            ),
          ],
        ),
        // 终局覆盖
        if (isFinished || phase == _LobbyPhase.ended)
          _buildOverlay(gs, theme),
      ],
    );
  }

  Widget _buildBoardOverlay(GameState gs, double cellSize, BoardThemeData theme, double distance) {
    final toc = _touchCtrl;

    // 确认阶段的预览棋子位置
    final pendingCellId = toc.pendingTargetCellId;
    final topId = pendingCellId != null && gs.currentPlayerIsTop
        ? pendingCellId
        : _displayCellId(gs.topPlayerId);
    final bottomId = pendingCellId != null && !gs.currentPlayerIsTop
        ? pendingCellId
        : _displayCellId(gs.bottomPlayerId);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ChessWall(history: _displayHistory, cellSize: cellSize, theme: theme),
        PlayerPrompt(
          validMoves: _displayValidMoves(),
          cellSize: cellSize, theme: theme,
          visible: toc.targetCellId != null,
        ),
        ChessPlayer(cellId: topId, cellSize: cellSize, color: theme.piecePlayerA),
        ChessPlayer(cellId: bottomId, cellSize: cellSize, color: theme.piecePlayerB),
        if (pendingCellId != null)
          Positioned(
            left: (pendingCellId % 9) * distance + 1,
            top: (pendingCellId ~/ 9) * distance + 1,
            child: Container(
              width: cellSize - 2, height: cellSize - 2,
              decoration: BoxDecoration(
                color: theme.validMoveRing.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: theme.validMoveRing.withValues(alpha: 0.7), width: 2),
              ),
            ),
          ),
        WallPrompt(
          wallData: toc.previewWall ?? toc.pendingWall,
          cellSize: cellSize, theme: theme,
          isValid: toc.wallPreviewValid,
          visible: toc.previewWall != null || toc.pendingWall != null,
        ),
      ],
    );
  }

  Widget _buildPlayerPanel(BoardThemeData theme, {required bool rotated, required bool isTop}) {
    final gs = _gameState;
    final isRunning = gs.status == GameStatus.running;
    final isCurrentTurn = isTop == gs.currentPlayerIsTop;
    final active = isRunning && isCurrentTurn;

    final playerSteps = gs.history.where((m) => !m.isWall && m.isTopPlayer == isTop).length;
    final wallsPlaced = isTop ? gs.topWallsPlaced : gs.bottomWallsPlaced;
    final remaining = SurroundGameConstants.wallCountPerPlayer - wallsPlaced;
    final toc = _touchCtrl;

    return PlayerPanel(
      rotated: rotated, active: active, isTop: isTop,
      mode: toc.mode, phase: toc.phase,
      canPlaceWall: remaining > 0,
      playerSteps: playerSteps,
      remainingWalls: remaining,
      canRequestUndo: false,
      onToggleMode: active ? () { _touchCtrl.toggleMode(); setState(() {}); } : null,
      onConfirm: (toc.phase == TouchPhase.confirming && active) ? _onConfirm : null,
      onCancel: (toc.phase == TouchPhase.confirming && active)
          ? () { _touchCtrl.cancelAction(); setState(() {}); } : null,
      onRotate: (toc.phase == TouchPhase.confirming && active)
          ? () { _touchCtrl.rotatePendingWall(
              validateWall: (wx, wy, o) => QuoridorEngine.isWallPlacementValid(
                gs.wallGrid, gs.adjacency, gs.topPlayerId, gs.bottomPlayerId,
                wx, _mirrorY(wy), o,
              ),
            ); setState(() {}); } : null,
      pendingWall: toc.pendingWall,
    );
  }

  Widget _bottomAction(IconData icon, String label, BoardThemeData theme, VoidCallback? onTap) {
    final color = theme.btnText.withValues(alpha: onTap != null ? 0.6 : 0.25);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ]),
    );
  }

  Future<void> _reset() async {
    _touchCtrl.reset();
    await widget.handle.applyAction(type: 'RESET', params: const {});
  }

  Widget _buildOverlay(GameState gs, BoardThemeData theme) {
    String msg;
    Color winColor;
    if (gs.status == GameStatus.topWin) {
      msg = _isHost ? '我方获胜！' : '上方获胜';
      winColor = theme.piecePlayerA;
    } else if (gs.status == GameStatus.bottomWin) {
      msg = _isHost ? '对方获胜' : '我方获胜！';
      winColor = theme.piecePlayerB;
    } else {
      msg = '平局';
      winColor = Colors.orange;
    }
    return Container(
      color: Colors.black.withValues(alpha: 0.5),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          decoration: BoxDecoration(
            color: theme.panelBg, borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 20)],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.emoji_events, size: 48, color: winColor),
            const SizedBox(height: 12),
            Text(msg, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: winColor)),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _isHost ? _reset : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: winColor,
                side: BorderSide(color: winColor),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              child: const Text('再来一局'),
            ),
          ]),
        ),
      ),
    );
  }

  Map<String, String> _extractPlayers() {
    final raw = _snap?.context['players'];
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
  }
}
