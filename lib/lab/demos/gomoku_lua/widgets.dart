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
  /// 待确认落子点：点击空交点后进入待确认，确认才发 MOVE。
  /// null = 无待确认。回合切换/对手落子时自动清除。
  (int, int)? _pendingPoint;
  /// 已声明过胜利（防死循环：WIN 万一被拒/网络抖动，不重复发导致闪屏）。
  /// RESET/新局开始时重置。
  bool _winDeclared = false;

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
    // 回合切换（落子数变化）→ 清掉待确认状态，防止跨回合残留
    final prevMoveCount = _moves.length;
    setState(() {
      _snap = s;
      _rebuild(s);
    });
    if (_moves.length != prevMoveCount && _pendingPoint != null) {
      setState(() => _pendingPoint = null);
    }
    if (_ackedLocally && (s.state != 'lobby' && s.state != 'ready')) {
      setState(() => _ackedLocally = false);
    }
    // RESET 回到 lobby → 新局开始，重置胜利声明标志
    if (s.state == 'lobby' && _winDeclared) {
      _winDeclared = false;
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
  Future<void> _reset() async {
    setState(() => _pendingPoint = null);
    await _room.reset();
  }

  /// 点击交点 → 进入待确认（不直接落子）。当前回合方 + 空格才接受。
  /// 再次点击同一交点 = 取消；点击别的空交点 = 改主意切换。
  void _setPending(Offset localPos, double side) {
    if (!_isMyTurn) return;
    if (_snap?.state != 'playing') return;
    final point = _pointFromLocal(localPos, side);
    if (point == null) return;
    final (x, y) = point;
    if (_board[y][x] != 0) return;  // 已有子
    setState(() {
      _pendingPoint = (_pendingPoint == (x, y)) ? null : (x, y);
    });
  }

  /// 确认落子 → 发 MOVE + 清 pending。
  Future<void> _confirmMove() async {
    final p = _pendingPoint;
    if (p == null) return;
    if (!_isMyTurn) { setState(() => _pendingPoint = null); return; }
    final (x, y) = p;
    if (_board[y][x] != 0) { setState(() => _pendingPoint = null); return; }
    setState(() => _pendingPoint = null);
    await _room.move(GomokuMove(x: x, y: y, isBlack: _imBlack));
  }

  void _cancelPending() => setState(() => _pendingPoint = null);

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
  /// _winDeclared 防死循环：WIN 万一被拒或网络抖动，不重复发导致闪屏。
  void _maybeDeclareWin() {
    if (_winDeclared) return;
    if (_snap?.state != 'playing') return;
    if (_moves.isEmpty) return;
    final last = _moves.last;
    if (GomokuRoom.hasFiveInRow(_board, last.x, last.y)) {
      _winDeclared = true;
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
        // 顶部状态条：轮到谁 / 待确认提示
        _buildTurnBar(theme),
        Expanded(
          child: Center(child: LayoutBuilder(builder: (context, constraints) {
            final side = constraints.biggest.shortestSide;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              // 点击空交点 → 进入待确认（不直接落子，需确认按钮）
              onTapDown: (d) => _setPending(d.localPosition, side),
              child: GomokuBoardWidget(
                board: _board,
                lastMove: _moves.isEmpty ? null : (_moves.last.x, _moves.last.y),
                // 待确认时显示半透明预览子（仅当前回合方）
                previewPoint: (_isMyTurn && _pendingPoint != null) ? _pendingPoint : null,
                previewIsBlack: _imBlack,
              ),
            );
          })),
        ),
        // 待确认按钮条 —— 固定占位（即便不在待确认状态也保留高度），
        // 避免其出现/消失撑动上方 Expanded，导致棋盘在回合切换时上下抖动
        _buildConfirmSlot(theme),
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
    // 待确认时改文案，提示用户确认或换点
    final String statusText;
    if (_pendingPoint != null && isMine) {
      final (px, py) = _pendingPoint!;
      // 棋谱坐标：列 A-O，行 1-15（从下往上）— 视觉直观
      final colLabel = String.fromCharCode('A'.codeUnitAt(0) + px);
      final rowLabel = kGomokuSize - py;
      statusText = '落子 $colLabel$rowLabel？点别处改点';
    } else {
      statusText = isMine ? '轮到你（$myLabel）落子' : '等待 $turnLabel 落子…';
    }
    // 固定高度：文案字数变化（轮到谁 / 等待谁 / 待确认坐标）也保持条高一致，
    // 避免高度抖动传导到下方 Expanded，导致棋盘垂直居中位置上下偏移。
    return SizedBox(
      height: kGomokuTurnBarHeight,
      width: double.infinity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: theme.panelBg.withValues(alpha: 0.5),
        alignment: Alignment.center,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 14, color: turnColor),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              statusText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.btnText, fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 8),
          // 我方颜色标识
          Container(
            width: 12, height: 12,
            decoration: BoxDecoration(color: myColor, shape: BoxShape.circle,
              border: Border.all(color: theme.panelBorder)),
          ),
        ]),
      ),
    );
  }

  /// 待确认按钮条（固定占位）。
  ///
  /// 无论是否处于待确认状态，都占据 [kGomokuConfirmBarHeight] 高度 —— 不待确认时
  /// 渲染空占位，使上方棋盘区域（Expanded）高度恒定，落子/回合切换时棋盘不再抖动。
  Widget _buildConfirmSlot(BoardThemeData theme) {
    if (_pendingPoint == null) {
      return const SizedBox(height: kGomokuConfirmBarHeight, width: double.infinity);
    }
    final myColor = _imBlack ? _blackColor : _whiteColor;
    return SizedBox(
      height: kGomokuConfirmBarHeight,
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          OutlinedButton.icon(
            onPressed: _cancelPending,
            icon: const Icon(Icons.close, size: 18),
            label: const Text('取消'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade400,
              side: BorderSide(color: Colors.red.shade400),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: _confirmMove,
            icon: const Icon(Icons.check, size: 18, color: Colors.white),
            label: const Text('确认落子', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: myColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            ),
          ),
        ]),
      ),
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
