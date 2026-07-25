// lib/lab/demos/surround_game_lua/widgets.dart
// 围追堵截 Lua 版 — UI 组件：SetupPage / JoinPage / OnlineGamePage
//
// 布局与 LAN host/client 完全一致：
// - host = flipY=true（触摸 y 镜像 + 棋盘整体翻转）
// - client = flipY=false（基线）
// - 棋盘 + 单一 PlayerPanel（只显示自己的，底部）

import 'dart:async';

import 'package:flutter/material.dart';

import 'constants.dart';
import 'engine.dart' show SgRoom, QuoridorEngine, GameState, MoveRecord,
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
// Online Game Page — LAN-style 单面板布局
//
// host 端：棋盘整体 y 翻转 + 触摸 y 镜像；isMyTurn = (host==topPlayer)
// client 端：棋盘原样；isMyTurn = (client==topPlayer)
// 任意时刻都只显示自己的 PlayerPanel（底部）
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
  late final SgRoom _room;
  TouchController _touchCtrl = TouchController();  // 仅在 _ensureTouchController 里首次校准；host 端在坐标回调里镜像
  String? _lastUndoRequester;
  /// 本地乐观状态：lobby 阶段点了"准备好了"立即置 true，不等服务端回包。
  /// 离开 lobby（→ ready/playing/ended）时清除。
  bool _ackedLocally = false;

  @override
  void initState() {
    super.initState();
    _room = SgRoom(widget.handle);
    _snap = widget.handle.latest;
    _rebuildGs(_snap);
    _sub = widget.handle.snapshots.listen(_onSnapshot);
  }

  void _onSnapshot(Snapshot s) {
    if (!mounted) return;
    final prevMyTurn = _isMyTurn;
    setState(() {
      _snap = s;
      _rebuildGs(s);
    });
    // 回合切换时，清掉残留的触摸/确认状态（防止按钮卡在 confirming）
    if (prevMyTurn && !_isMyTurn) {
      _touchCtrl.reset();
      setState(() {});
    }
    // 离开 lobby 阶段 → 清除本地 ACK 乐观标记
    if (_ackedLocally && (s.state != 'lobby' && s.state != 'ready')) {
      setState(() => _ackedLocally = false);
    }
    // 胜利检测：本地 QuoridorEngine 从权威 history 重建出 gs.status != running，
    // 但 Lua state 还在 playing（Lua 没有引擎，无法自行判胜）→ 发 WIN 让服务端记 ended+winner。
    // 双方客户端都会检测到，幂等：state 已 ended 时 Lua 忽略第二个 WIN。
    _maybeDeclareWin();
    _maybeShowUndoIncomingDialog();
  }

  /// 某方走到终点 / 平局时，向服务端声明胜利。
  void _maybeDeclareWin() {
    if (_snap?.state != 'playing') return;
    final status = _gs.status;
    if (status == GameStatus.running) return;
    final String winner;
    if (status == GameStatus.topWin) {
      winner = 'top';
    } else if (status == GameStatus.bottomWin) {
      winner = 'bottom';
    } else {
      // draw（围追堵截当前规则无平局，预留）
      return;
    }
    _room.declareWin(winner);
  }

  void _rebuildGs(Snapshot? s) {
    final snap = s ?? _snap ?? widget.handle.latest;
    _gs = SgRoom.rebuildGameState(snap);
  }

  @override
  void dispose() { _sub?.cancel(); super.dispose(); }

  // ── 网络动作 ──
  /// ACK：立即乐观置 _ackedLocally，UI 立刻有反馈；服务端 snapshot 回包时已正确。
  /// 不需要等到服务端 ACK 才显示"已准备"。
  Future<void> _ack() async {
    if (_ackedLocally) return;
    setState(() => _ackedLocally = true);
    try {
      await _room.ack();
    } catch (_) {
      if (mounted) setState(() => _ackedLocally = false);
    }
  }
  Future<void> _deal() async {
    try {
      await _room.deal();
      _touchCtrl.reset();
    } catch (_) {}
  }

  Future<void> _reset() async {
    _touchCtrl.reset();
    await _room.reset();
  }

  // ── 棋盘判断 ──

  bool get _flipY => widget.isHostSide;

  /// "我是不是 top player" — 用服务端权威字段 top_player_id 推导。
  /// 与"我是 host"等价，但语义独立：万一未来出现"host 旁观、玩家换人"的场景，
  /// 这个标志仍然正确表达"我在棋盘上对应 top/bottom"。
  bool get _imTop {
    final topId = SgRoom.topPlayerId(_snap);
    if (topId == null) return false;
    return _room.deviceId == topId;
  }

  /// 当前回合是否轮到自己
  /// 通用语义：`imTop == gs.currentPlayerIsTop`（与 host/client 视角无关）
  bool get _isMyTurn {
    if (_snap == null) return false;
    return _imTop == _gs.currentPlayerIsTop;
  }

  bool _validateWall(int wx, int wy, WallOrientation o) {
    return QuoridorEngine.isWallPlacementValid(
      _gs.wallGrid, _gs.adjacency, _gs.topPlayerId, _gs.bottomPlayerId,
      wx, wy, o,
    );
  }

  // ── 触摸 ──

  /// 把 Listener 内的 localPosition 转成"棋盘规范坐标系"的 localPosition。
  ///
  /// host 端棋盘经 Transform.flip(flipY: true) 视觉翻转，但 Listener 在
  /// Transform.flip 之外 —— event.localPosition 是 Stack 局部坐标，与视觉
  /// 是否翻转无关。所以棋盘视觉顶部对应 Listener 的 y=0（视觉上 = 对方棋子），
  /// 棋盘视觉底部对应 y=boardSize（视觉上 = 自己棋子）。
  ///
  /// 服务端存规范坐标：host 自己 = 规范 y=0。所以必须把 localPosition 沿
  /// boardSize 中线镜像后，才等同于"按规范坐标系看视觉棋盘"。
  Offset _canonicalLocalPosition(Offset pos) =>
      _flipY ? Offset(pos.dx, _boardSizePx - pos.dy) : pos;

  /// 棋盘当前像素边长（Stack 内 Listener 的坐标系全长）
  double _boardSizePx = 0;

  void _onPointerDown(Offset pos, double cs, double dist) {
    if (!_isMyTurn) return;
    final gs = _gs;
    final currentId = gs.currentPlayerIsTop ? gs.topPlayerId : gs.bottomPlayerId;
    final wallsPlaced = gs.currentPlayerIsTop ? gs.topWallsPlaced : gs.bottomWallsPlaced;
    final remaining = SurroundGameConstants.wallCountPerPlayer - wallsPlaced;
    _touchCtrl.handleTouchBegan(_canonicalLocalPosition(pos), cs, dist,
      isRunning: gs.status == GameStatus.running,
      currentPlayerId: currentId,
      canPlaceWall: remaining > 0,
      validateWall: _validateWall,
    );
    setState(() {});
  }

  void _onPointerMove(Offset pos, double cs, double dist) {
    if (!_isMyTurn) return;
    _touchCtrl.handleTouchMoved(_canonicalLocalPosition(pos), cs, dist, validateWall: _validateWall);
    setState(() {});
  }

  void _onPointerUp(Offset pos, double cs, double dist) {
    if (!_isMyTurn) return;
    _touchCtrl.handleTouchEnded(_canonicalLocalPosition(pos), cs, dist,
      isTopTurn: _gs.currentPlayerIsTop,
      validMoves: _gs.validMoves,
      validateWall: _validateWall,
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
      _room.move(MoveRecord.wall(
        x: toc.pendingWall!.x, y: toc.pendingWall!.y,
        orientation: toc.pendingWall!.o,
        isTopPlayer: _gs.currentPlayerIsTop,
      ));
    } else if (toc.pendingTargetCellId != null) {
      _room.move(MoveRecord.move(
        cellId: toc.pendingTargetCellId!,
        isTopPlayer: _gs.currentPlayerIsTop,
      ));
    }
    toc.reset();
    setState(() {});
  }

  // ── 悔棋对话框（我是对手时弹） ──

  Future<void> _maybeShowUndoIncomingDialog() async {
    final requester = SgRoom.undoRequester(_snap);
    if (requester == null) {
      _lastUndoRequester = null;
      return;
    }
    if (requester == _lastUndoRequester) return;
    if (requester == _room.deviceId) return;
    _lastUndoRequester = requester;
    if (!mounted) return;
    final accept = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('对手请求悔棋'),
        content: const Text('是否同意撤销上一步？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('拒绝')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('同意')),
        ],
      ),
    );
    if (accept != null) await _room.respondUndo(accepted: accept);
  }

  void _showUndoRequestConfirm() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('请求悔棋'),
        content: const Text('将撤销上一步，回合回到上一步的执行者。\n需对手同意才生效。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () { Navigator.pop(ctx); _room.requestUndo(); }, child: const Text('发起')),
        ],
      ),
    );
  }

  void _showResignConfirm() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('认输'),
        content: const Text('确认认输？此局结束。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('认输')),
        ],
      ),
    );
    if (confirm == true) await _room.resign();
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final theme = BoardTheme.of(context);
    final phase = _snap?.state;

    if (phase == null || phase == 'lobby') return _buildLobby(theme);
    if (phase == 'ready') return _buildReadyWait(theme);
    if (phase == 'ended') return _buildFinished(theme);
    return _buildPlaying(theme);
  }

  // ── 阶段：等待对手 ──

  Widget _buildLobby(BoardThemeData theme) {
    final code = _snap?.roomCode ?? '------';
    final players = SgRoom.players(_snap);
    final readyMap = SgRoom.readyMap(_snap);
    final myId = _room.deviceId;
    // 服务端回包的 ACK 状态 OR 本地乐观标记（点了之后立即显示 ✓，不等回包）
    final iAmReady = _ackedLocally || (readyMap[myId] == true);
    return Scaffold(
      backgroundColor: theme.boardSurface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.hourglass_top, size: 64, color: Colors.orange),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Text(code, style: const TextStyle(
                    fontSize: 28, fontWeight: FontWeight.bold,
                    letterSpacing: 6, color: Colors.orange)),
              ),
              const SizedBox(height: 16),
              Text('等待对手加入…', style: TextStyle(color: theme.btnSub, fontSize: 13)),
              const SizedBox(height: 24),
              ...players.entries.map((e) {
                final isMe = e.key == myId;
                final isReady = readyMap[e.key] == true;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isReady
                        ? Colors.green
                        : (isMe ? Colors.orange : Colors.grey),
                    child: Icon(
                      isReady ? Icons.check : Icons.person,
                      color: Colors.white, size: 20,
                    ),
                  ),
                  title: Text(
                    '${e.value}${isMe ? " (我)" : ""}',
                    style: TextStyle(color: theme.btnText),
                  ),
                  trailing: Text(
                    isReady ? '已准备 ✓' : '未准备',
                    style: TextStyle(
                      color: isReady ? Colors.green.shade400 : theme.btnSub,
                      fontSize: 13,
                    ),
                  ),
                );
              }),
              if (players.length >= 2) ...[
                const SizedBox(height: 16),
                // ACK 后立即变 "已准备 ✓" + disabled，不等服务端回包
                OutlinedButton.icon(
                  onPressed: iAmReady ? null : _ack,
                  icon: Icon(iAmReady ? Icons.check_circle : Icons.check_circle_outlined),
                  label: Text(iAmReady ? '已准备 ✓' : '准备好了'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: iAmReady ? Colors.green : Colors.green.shade400,
                    side: BorderSide(color: iAmReady ? Colors.green : Colors.green.shade400),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    minimumSize: const Size(200, 48),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildReadyWait(BoardThemeData theme) {
    return Scaffold(
      backgroundColor: theme.boardSurface,
      body: SafeArea(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.hourglass_top, size: 48, color: Colors.orange),
        const SizedBox(height: 16),
        Text('双方已准备好', style: TextStyle(fontSize: 18, color: theme.btnText)),
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
          Text('等待房主开始…', style: TextStyle(color: theme.btnSub)),
      ]))),
    );
  }

  // ── 阶段：游戏中（LAN 风格单面板） ──

  Widget _buildPlaying(BoardThemeData theme) {
    final gs = _gs;
    final isRunning = gs.status == GameStatus.running;
    // TouchView guard：
    // ① phase==playing（Lua 状态机已进入 playing）
    // ② _snap 已到位（_gs 反映真实历史）
    // ③ 轮到本方走（imTop == currentPlayerIsTop）
    // 注意：history 可为空（开局先手玩家第一步），不放宽这一步会导致开局 TouchView 永不挂载。
    final canMountTouchView = _snap != null
        && _snap?.state == 'playing'
        && _isMyTurn;
    return Scaffold(
      backgroundColor: theme.boardSurface,
      body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cs = w / 11;
        final boardSize = w;
        _boardSizePx = boardSize;  // 给触摸坐标镜像用
        // host 端：touch controller 用镜像版；client 端用基线
        _ensureTouchController(boardSize);

        return Column(children: [
          Expanded(
            child: Center(child: SizedBox(
              width: boardSize, height: boardSize,
              child: Stack(clipBehavior: Clip.none, children: [
                // 翻转的绘制层（host 镜像，client 原样）
                if (_flipY)
                  Transform.flip(flipY: true, child: _drawLayer(cs, boardSize, theme))
                else
                  _drawLayer(cs, boardSize, theme),
                // 确认按钮层：放在外层 Stack（不被 _drawLayer 的 flipY 翻转）。
                // host 端坐标做 y 镜像后再传给 ConfirmActions，
                // 让按钮视觉位置正确（在棋子视觉下方，与 guest/LAN bottom 一致）。
                _buildConfirmActions(cs, boardSize, theme),
                // 触摸层（仅本方回合挂载）
                if (canMountTouchView)
                  TouchView(
                    cellSize: cs, distance: cs * 1.25,
                    onPointerDown: _onPointerDown,
                    onPointerMove: _onPointerMove,
                    onPointerUp: _onPointerUp,
                    onPointerCancel: _onPointerCancel,
                  ),
              ]),
            )),
          ),
          // 底部自己的 PlayerPanel（只显示自己）
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 6),
            child: Center(child: _buildPlayerPanel(theme)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (isRunning)
                _bottomAction(Icons.flag_outlined, '认输', _showResignConfirm, theme),
              if (isRunning) const SizedBox(width: 16),
              if (_room.isHost)
                _bottomAction(Icons.refresh, '重新开始', _reset, theme),
              if (_room.isHost) const SizedBox(width: 16),
              _bottomAction(Icons.exit_to_app, '退出', widget.onLeave, theme),
            ]),
          ),
        ]);
      })),
    );
  }

  void _ensureTouchController(double boardSize) {
    // 只在首次或类型不对时重建，避免每次 build 重置触摸状态（client 端尤其严重）。
    if (_touchCtrl is! TouchController) {
      _touchCtrl = TouchController();
    }
  }

  Widget _drawLayer(double cs, double boardSize, BoardThemeData theme) {
    final gs = _gs;
    final toc = _touchCtrl;
    final pendingCellId = toc.pendingTargetCellId;
    final topId = pendingCellId != null && gs.currentPlayerIsTop
        ? pendingCellId
        : gs.topPlayerId;
    final bottomId = pendingCellId != null && !gs.currentPlayerIsTop
        ? pendingCellId
        : gs.bottomPlayerId;

    return Stack(clipBehavior: Clip.none, children: [
      ChessBoard(cellSize: cs, theme: theme),
      ChessWall(history: gs.history, cellSize: cs, theme: theme),
      PlayerPrompt(validMoves: gs.validMoves, cellSize: cs, theme: theme,
          visible: toc.targetCellId != null),
      ChessPlayer(cellId: topId, cellSize: cs, color: theme.piecePlayerA),
      ChessPlayer(cellId: bottomId, cellSize: cs, color: theme.piecePlayerB),
      if (pendingCellId != null)
        _PendingHighlight(cellId: pendingCellId, cellSize: cs, theme: theme),
      WallPrompt(wallData: toc.previewWall ?? toc.pendingWall,
          cellSize: cs, theme: theme,
          isValid: toc.wallPreviewValid,
          visible: toc.previewWall != null || toc.pendingWall != null),
      if (toc.dragOffset != null && toc.targetCellId != null)
        _FloatingPiece(offset: toc.dragOffset!,
            color: gs.currentPlayerIsTop ? theme.piecePlayerA : theme.piecePlayerB,
            cellSize: cs),
      // 注意：ConfirmActions 不放在 _drawLayer 里（见 _buildPlaying 外层 Stack），
      // 因为它在 host 端不能被外层 Transform.flip 翻转——否则按钮会上下镜像。
    ]);
  }

  /// 确认按钮层 — 放在外层 Stack 直接子节点（不被 _drawLayer 的 flipY 翻转）。
  ///
  /// host 端把规范坐标的 cellId/wall 做 y 镜像后再传给 ConfirmActions，
  /// 这样按钮按视觉坐标系定位，出现在棋子视觉下方（与 guest/LAN bottom 一致）。
  Widget _buildConfirmActions(double cs, double boardSize, BoardThemeData theme) {
    final toc = _touchCtrl;
    int? visualCellId = toc.pendingTargetCellId;
    ({int x, int y, WallOrientation o})? visualWall = toc.pendingWall;
    if (_flipY) {
      // host 端：规范 y → 视觉 y = 8 - 规范 y
      if (visualCellId != null) {
        final x = visualCellId % 9;
        final y = visualCellId ~/ 9;
        visualCellId = (8 - y) * 9 + x;
      }
      if (visualWall != null) {
        visualWall = (x: visualWall.x, y: 8 - visualWall.y, o: visualWall.o);
      }
    }
    return ConfirmActions(
      phase: toc.phase,
      pendingTargetCellId: visualCellId,
      pendingWall: visualWall,
      // 互联网版双方视觉都"从底部看"，按钮图标都不翻转 → isTopTurn=false。
      isTopTurn: false,
      cellSize: cs, boardSize: boardSize, theme: theme,
      onConfirm: _onConfirm,
      onCancel: () { toc.cancelAction(); setState(() {}); },
      onRotate: () {
        toc.rotatePendingWall(validateWall: _validateWall);
        setState(() {});
      },
    );
  }

  Widget _buildPlayerPanel(BoardThemeData theme) {
    final gs = _gs;
    final isRunning = gs.status == GameStatus.running;
    // 我是 top：active = currentPlayerIsTop；我是 bottom：active = !currentPlayerIsTop
    final myIsTop = _imTop;
    final active = isRunning && myIsTop == gs.currentPlayerIsTop;
    final toc = _touchCtrl;
    final steps = gs.history.where((m) => !m.isWall && m.isTopPlayer == myIsTop).length;
    final walls = myIsTop ? gs.topWallsPlaced : gs.bottomWallsPlaced;
    final canUndo = SgRoom.canRequestUndo(_snap, gs, _room.deviceId);
    return PlayerPanel(
      rotated: false,  // 底部面板不旋转；棋盘本身已翻转
      active: active,
      isTop: myIsTop,
      mode: toc.mode, phase: toc.phase,
      canPlaceWall: SurroundGameConstants.wallCountPerPlayer - walls > 0,
      playerSteps: steps,
      remainingWalls: SurroundGameConstants.wallCountPerPlayer - walls,
      canRequestUndo: canUndo,
      onToggleMode: active ? () { toc.toggleMode(); setState(() {}); } : null,
      onConfirm: (toc.phase == TouchPhase.confirming && active) ? _onConfirm : null,
      onCancel: (toc.phase == TouchPhase.confirming && active)
          ? () { toc.cancelAction(); setState(() {}); } : null,
      onRotate: (toc.phase == TouchPhase.confirming && active)
          ? () { toc.rotatePendingWall(validateWall: _validateWall); setState(() {}); } : null,
      onUndoRequest: canUndo ? _showUndoRequestConfirm : null,
      pendingWall: toc.pendingWall,
    );
  }

  Widget _bottomAction(IconData icon, String label, VoidCallback? onTap, BoardThemeData theme) {
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

  Widget _buildFinished(BoardThemeData theme) {
    final gs = _gs;
    final imTop = _imTop;
    // 优先用服务端权威 winner 字段（WIN/RESIGN 时 Lua 写入）；
    // fallback 到本地 gs.status（snapshot 还没带回 ended 时容错）。
    final w = SgRoom.winner(_snap);
    final isTopWin = w == 'top' || (w == null && gs.status == GameStatus.topWin);
    final isDraw = w == null && gs.status == GameStatus.draw;
    // 角色感知消息：
    //   我是 top：topWin → 我方获胜；bottomWin → 对方获胜
    //   我是 bottom：topWin → 对方获胜；bottomWin → 我方获胜
    final String msg;
    if (isDraw) {
      msg = '平局';
    } else if (isTopWin == imTop) {
      msg = '我方获胜！';
    } else {
      msg = '对方获胜';
    }
    final winColor = isDraw
        ? Colors.orange
        : (isTopWin ? theme.piecePlayerA : theme.piecePlayerB);
    return Scaffold(
      backgroundColor: theme.boardSurface,
      body: SafeArea(child: Stack(children: [
        LayoutBuilder(builder: (context, constraints) {
          final w = constraints.maxWidth;
          final cs = w / 11;
          final boardSize = w;
          _ensureTouchController(boardSize);
          return Center(child: SizedBox(
            width: boardSize, height: boardSize,
            child: Stack(clipBehavior: Clip.none, children: [
              if (_flipY)
                Transform.flip(flipY: true, child: _drawLayer(cs, boardSize, theme))
              else
                _drawLayer(cs, boardSize, theme),
            ]),
          ));
        }),
        Container(color: Colors.black54, child: Center(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          decoration: BoxDecoration(color: theme.panelBg, borderRadius: BorderRadius.circular(16)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.emoji_events, size: 48, color: winColor),
            const SizedBox(height: 12),
            Text(msg, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: winColor)),
            const SizedBox(height: 16),
            // 再来一局：仅房主可操作。客方显示等房主提示，避免给"看着可点"的按钮。
            if (_room.isHost)
              OutlinedButton(
                onPressed: _reset,
                style: OutlinedButton.styleFrom(
                  foregroundColor: winColor, side: BorderSide(color: winColor),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                child: const Text('再来一局'),
              )
            else
              Text(
                '等待房主开始下一局…',
                style: TextStyle(color: theme.btnSub, fontSize: 13),
              ),
          ]),
        ))),
      ])),
    );
  }
}

// ── 待确认高亮 ──
class _PendingHighlight extends StatelessWidget {
  const _PendingHighlight({
    required this.cellId, required this.cellSize, required this.theme,
  });
  final int cellId;
  final double cellSize;
  final BoardThemeData theme;

  @override
  Widget build(BuildContext context) {
    final distance = cellSize * 1.25;
    final x = (cellId % 9).toDouble();
    final y = (cellId ~/ 9).toDouble();
    return Positioned(
      left: x * distance + 1, top: y * distance + 1,
      child: Container(
        width: cellSize - 2, height: cellSize - 2,
        decoration: BoxDecoration(
          color: theme.validMoveRing.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: theme.validMoveRing.withValues(alpha: 0.7), width: 2),
        ),
      ),
    );
  }
}

// ── 拖动时的浮动棋子 ──
class _FloatingPiece extends StatelessWidget {
  const _FloatingPiece({required this.offset, required this.color, required this.cellSize});
  final Offset offset;
  final Color color;
  final double cellSize;

  @override
  Widget build(BuildContext context) {
    final pieceSize = cellSize * 0.7;
    return Positioned(
      left: offset.dx - pieceSize / 2,
      top: offset.dy - pieceSize / 2,
      child: Container(
        width: pieceSize, height: pieceSize,
        decoration: BoxDecoration(
          color: color, shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.75), width: 2.5),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 8, offset: const Offset(0, 3))],
        ),
      ),
    );
  }
}