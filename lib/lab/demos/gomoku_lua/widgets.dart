// lib/lab/demos/gomoku_lua/widgets.dart
// 五子棋 Lua 版 — UI 组件：SetupPage / JoinPage / OnlineGamePage
//
// 布局与 surround_game_lua 一致，差异：
//   - 棋盘用 GomokuBoardWidget（网格线 + 交点落子）
//   - 无镜像翻转（对称棋盘）
//   - 角色字段 black_player_id（host=黑先手）
//   - 胜负 = 连五，客户端本地判定后发 WIN

import 'dart:async';

import 'package:flutter/material.dart';

import 'constants.dart';
import 'engine.dart' show
    GomokuRoom, GomokuMove, GomokuBoard, kGomokuScript,
    Snapshot, RoomHandle, RelayV3Transport, kGomokuSize;
import 'board.dart' show GomokuBoardWidget;
import 'package:xiaodouzi_fr/core/surround_game/board_theme.dart';

// ══════════════════════════════════════════════════════════════
// Setup Page（建房）
// ══════════════════════════════════════════════════════════════

class SetupPage extends StatefulWidget {
  const SetupPage({super.key, required this.onCreated});
  final void Function(RoomHandle) onCreated;
  @override State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _aliasCtrl = TextEditingController(text: '黑方');
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    GomokuAliasPrefs.load().then((v) {
      if (mounted && v.isNotEmpty) setState(() => _aliasCtrl.text = v);
    });
  }

  @override
  void dispose() { _aliasCtrl.dispose(); super.dispose(); }

  Future<void> _create() async {
    setState(() { _busy = true; _error = null; });
    try {
      final t = RelayV3Transport(
        relayUrl: kGomokuRelayUrl,
        alias: _aliasCtrl.text.trim(),
        deviceId: 'gm-black-${DateTime.now().microsecondsSinceEpoch}',
      );
      await GomokuAliasPrefs.save(t.alias);
      final h = await t.createRoom(
        script: kGomokuScript,
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
  Widget build(BuildContext context) {
    final theme = BoardTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 64, color: _blackColor),
          const SizedBox(height: 16),
          Text('建房等对手（你执黑先手）',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.btnText)),
          const SizedBox(height: 24),
          TextField(
            controller: _aliasCtrl,
            decoration: InputDecoration(
              labelText: '昵称',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              labelStyle: TextStyle(color: theme.btnSub),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: theme.panelBorder)),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: _blackColor, width: 2)),
            ),
            style: TextStyle(color: theme.btnText),
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
              foregroundColor: _blackColor,
              side: BorderSide(color: _blackColor),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Join Page（加入）
// ══════════════════════════════════════════════════════════════

class JoinPage extends StatefulWidget {
  const JoinPage({super.key, required this.onJoined});
  final void Function(RoomHandle) onJoined;
  @override State<JoinPage> createState() => _JoinPageState();
}

class _JoinPageState extends State<JoinPage> {
  final _aliasCtrl = TextEditingController(text: '白方');
  final _codeCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    GomokuAliasPrefs.load().then((v) {
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
        relayUrl: kGomokuRelayUrl,
        alias: _aliasCtrl.text.trim(),
        deviceId: 'gm-white-${DateTime.now().microsecondsSinceEpoch}',
      );
      await GomokuAliasPrefs.save(t.alias);
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
    final theme = BoardTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle_outlined, size: 64, color: _whiteColor),
            const SizedBox(height: 16),
            Text('加入房间（你执白后手）',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.btnText)),
            const SizedBox(height: 24),
            TextField(
              controller: _aliasCtrl,
              decoration: InputDecoration(
                labelText: '昵称',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                labelStyle: TextStyle(color: theme.btnSub),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: theme.panelBorder)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: _whiteColor, width: 2)),
              ),
              style: TextStyle(color: theme.btnText),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codeCtrl,
              decoration: InputDecoration(
                labelText: '房间码',
                hintText: '6 位数字',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                labelStyle: TextStyle(color: theme.btnSub),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: theme.panelBorder)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: _whiteColor, width: 2)),
              ),
              style: TextStyle(color: theme.btnText),
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
                foregroundColor: _whiteColor,
                side: BorderSide(color: _whiteColor),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Online Game Page
//
// 双方看同一棋盘（无镜像）。落子在交点，点击直接落子（无需确认按钮，
// 五子棋落子简单，落错了就落错了——如需悔棋未来再加 UNDO）。
// ══════════════════════════════════════════════════════════════

const Color _blackColor = Color(0xFF2A2A2A);
const Color _whiteColor = Color(0xFF8A7A60);

class OnlineGamePage extends StatefulWidget {
  const OnlineGamePage({
    super.key,
    required this.handle,
    required this.onLeave,
  });
  final RoomHandle handle;
  final Future<void> Function() onLeave;

  @override State<OnlineGamePage> createState() => _OnlineGamePageState();
}

class _OnlineGamePageState extends State<OnlineGamePage> {
  StreamSubscription<Snapshot>? _sub;
  Snapshot? _snap;
  List<GomokuMove> _moves = const [];
  GomokuBoard _board = const [];
  /// 本地乐观状态：lobby 阶段点了"准备好了"立即置 true。
  bool _ackedLocally = false;
  /// 触摸悬停预览的交点
  (int, int)? _hoverPoint;

  late final GomokuRoom _room;

  @override
  void initState() {
    super.initState();
    _room = GomokuRoom(widget.handle);
    _snap = widget.handle.latest;
    _rebuild(_snap);
    _sub = widget.handle.snapshots.listen(_onSnapshot);
  }

  void _onSnapshot(Snapshot s) {
    if (!mounted) return;
    setState(() {
      _snap = s;
      _rebuild(s);
    });
    if (_ackedLocally && (s.state != 'lobby' && s.state != 'ready')) {
      setState(() => _ackedLocally = false);
    }
    // 连五判定：本地从权威 history 重建后检查最后一步是否连五 → 发 WIN
    _maybeDeclareWin();
  }

  void _rebuild(Snapshot? s) {
    _moves = GomokuRoom.rebuildMoves(s);
    _board = GomokuRoom.rebuildBoard(_moves);
  }

  @override
  void dispose() { _sub?.cancel(); super.dispose(); }

  // ── 角色与回合 ──

  /// 我是黑方？用服务端 black_player_id 判定（权威字段）。
  bool get _imBlack {
    final blackId = GomokuRoom.blackPlayerId(_snap);
    if (blackId == null) return false;
    return _room.deviceId == blackId;
  }

  /// 当前是否轮到我（黑方当前回合 == 我是黑方）
  bool get _isMyTurn {
    if (_snap == null) return false;
    final blackTurn = GomokuRoom.isBlackTurn(_moves);
    return blackTurn == _imBlack;
  }

  /// 按钮可点性：读服务端 action_permissions 表 + 自己角色（单点入口）。
  bool _canPerform(String action) => GomokuRoom.canPerform(
        action, _snap,
        isBlack: _imBlack,
        isMyTurn: _isMyTurn,
      );

  // ── 网络动作 ──

  Future<void> _ack() async {
    if (_ackedLocally) return;
    setState(() => _ackedLocally = true);
    try {
      await _room.ack();
    } catch (_) {
      if (mounted) setState(() => _ackedLocally = false);
    }
  }

  Future<void> _deal() async => _room.deal();
  Future<void> _reset() async => _room.reset();

  /// 落子：触摸坐标 → 最近交点 → MOVE。当前回合方 + 空格才落。
  Future<void> _placeStone(Offset localPos, double side) {
    if (!_isMyTurn) return Future.value();
    if (_snap?.state != 'playing') return Future.value();
    final point = _pointFromLocal(localPos, side);
    if (point == null) return Future.value();
    final (x, y) = point;
    if (_board[y][x] != 0) return Future.value();  // 已有子
    return _room.move(GomokuMove(x: x, y: y, isBlack: _imBlack));
  }

  /// 触摸坐标 → 最近交点 (x, y)。落点在 padding 外返回 null。
  (int, int)? _pointFromLocal(Offset pos, double side) {
    const padding = 16.0;
    final gridSize = side - padding * 2;
    final step = gridSize / (kGomokuSize - 1);
    final gx = (pos.dx - padding) / step;
    final gy = (pos.dy - padding) / step;
    // 四舍五入到最近交点
    final x = gx.round();
    final y = gy.round();
    if (x < 0 || x >= kGomokuSize || y < 0 || y >= kGomokuSize) return null;
    // 容差：触摸点离交点不超过半格才接受
    if ((gx - x).abs() > 0.5 || (gy - y).abs() > 0.5) return null;
    return (x, y);
  }

  /// 连五判定 → 发 WIN。双方都检测，幂等（state 已 ended 时 Lua 忽略）。
  void _maybeDeclareWin() {
    if (_snap?.state != 'playing') return;
    if (_moves.isEmpty) return;
    final last = _moves.last;
    if (GomokuRoom.hasFiveInRow(_board, last.x, last.y)) {
      _room.declareWin(last.isBlack ? 'black' : 'white');
    }
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

  // ── 阶段：等待对手 + 准备 ──

  Widget _buildLobby(BoardThemeData theme) {
    final code = _snap?.roomCode ?? '------';
    final players = GomokuRoom.players(_snap);
    final readyMap = GomokuRoom.readyMap(_snap);
    final myId = _room.deviceId;
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
                    backgroundColor: isReady ? Colors.green : (isMe ? Colors.orange : Colors.grey),
                    child: Icon(isReady ? Icons.check : Icons.person, color: Colors.white, size: 20),
                  ),
                  title: Text('${e.value}${isMe ? " (我)" : ""}', style: TextStyle(color: theme.btnText)),
                  trailing: Text(isReady ? '已准备 ✓' : '未准备',
                      style: TextStyle(color: isReady ? Colors.green.shade400 : theme.btnSub, fontSize: 13)),
                );
              }),
              if (players.length >= 2) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: (iAmReady || !_canPerform('ACK')) ? null : _ack,
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
    final canDeal = _canPerform('DEAL');
    return Scaffold(
      backgroundColor: theme.boardSurface,
      body: SafeArea(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.hourglass_top, size: 48, color: Colors.orange),
        const SizedBox(height: 16),
        Text('双方已准备好', style: TextStyle(fontSize: 18, color: theme.btnText)),
        const SizedBox(height: 24),
        if (canDeal)
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

  // ── 阶段：对战中 ──

  Widget _buildPlaying(BoardThemeData theme) {
    return Scaffold(
      backgroundColor: theme.boardSurface,
      body: SafeArea(child: Column(children: [
        // 顶部状态条：轮到谁
        _buildTurnBar(theme),
        Expanded(
          child: Center(child: LayoutBuilder(builder: (context, constraints) {
            final side = constraints.biggest.shortestSide;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) {
                // 落子（点击即落，五子棋无需确认）
                _placeStone(d.localPosition, side);
              },
              onPanUpdate: (d) {
                // 悬停预览（仅当前回合方）
                if (!_isMyTurn) return;
                final p = _pointFromLocal(d.localPosition, side);
                if (p != _hoverPoint) setState(() => _hoverPoint = p);
              },
              onPanEnd: (_) {
                if (_hoverPoint != null) setState(() => _hoverPoint = null);
              },
              child: GomokuBoardWidget(
                board: _board,
                lastMove: _moves.isEmpty ? null : (_moves.last.x, _moves.last.y),
                previewPoint: _isMyTurn ? _hoverPoint : null,
                previewIsBlack: _imBlack,
              ),
            );
          })),
        ),
        // 底部操作栏
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (_canPerform('RESIGN')) ...[
              _bottomAction(Icons.flag_outlined, '认输', _showResignConfirm, theme),
              const SizedBox(width: 16),
            ],
            if (_canPerform('RESET')) ...[
              _bottomAction(Icons.refresh, '重新开始', _reset, theme),
              const SizedBox(width: 16),
            ],
            _bottomAction(Icons.exit_to_app, '退出', widget.onLeave, theme),
          ]),
        ),
      ])),
    );
  }

  Widget _buildTurnBar(BoardThemeData theme) {
    final blackTurn = GomokuRoom.isBlackTurn(_moves);
    final isMine = blackTurn == _imBlack;
    final myColor = _imBlack ? _blackColor : _whiteColor;
    final myLabel = _imBlack ? '黑方' : '白方';
    final turnColor = blackTurn ? _blackColor : _whiteColor;
    final turnLabel = blackTurn ? '黑方' : '白方';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: theme.panelBg.withValues(alpha: 0.5),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.circle, size: 14, color: turnColor),
        const SizedBox(width: 8),
        Text(
          isMine ? '轮到你（$myLabel）落子' : '等待 $turnLabel 落子…',
          style: TextStyle(color: theme.btnText, fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(width: 8),
        // 我方颜色标识
        Container(
          width: 12, height: 12,
          decoration: BoxDecoration(color: myColor, shape: BoxShape.circle,
            border: Border.all(color: theme.panelBorder)),
        ),
      ]),
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

  // ── 阶段：终局 ──

  Widget _buildFinished(BoardThemeData theme) {
    final winner = GomokuRoom.winner(_snap);
    final isBlackWin = winner == 'black';
    // 角色感知：winner == 我方颜色 → 我赢
    final iWon = (isBlackWin == _imBlack);
    final msg = iWon ? '我方获胜！' : '对方获胜';
    final winColor = isBlackWin ? _blackColor : _whiteColor;
    return Scaffold(
      backgroundColor: theme.boardSurface,
      body: SafeArea(child: Stack(children: [
        // 棋盘背景（保留终局棋面）
        Center(child: LayoutBuilder(builder: (context, constraints) {
          return GomokuBoardWidget(
            board: _board,
            lastMove: _moves.isEmpty ? null : (_moves.last.x, _moves.last.y),
          );
        })),
        Container(color: Colors.black54, child: Center(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          decoration: BoxDecoration(color: theme.panelBg, borderRadius: BorderRadius.circular(16)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.emoji_events, size: 48, color: winColor),
            const SizedBox(height: 12),
            Text(msg, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: winColor)),
            const SizedBox(height: 8),
            Text('${isBlackWin ? "黑方" : "白方"}连五', style: TextStyle(color: theme.btnSub, fontSize: 13)),
            const SizedBox(height: 16),
            if (_canPerform('RESET'))
              OutlinedButton(
                onPressed: _reset,
                style: OutlinedButton.styleFrom(
                  foregroundColor: winColor, side: BorderSide(color: winColor),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                child: const Text('再来一局'),
              )
            else
              Text('等待房主开始下一局…', style: TextStyle(color: theme.btnSub, fontSize: 13)),
          ]),
        ))),
      ])),
    );
  }
}
