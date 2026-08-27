// lib/lab/demos/go_lua/widgets.dart
// 联机围棋 — UI 组件：LobbyEntryPage / OnlineGamePage
//
// 布局与 gomoku_lua 一致，差异：
//   - 棋盘用 GoBoardWidget（9×9 网格线 + 交点落子）
//   - 服务端权威提子/打劫/自杀，客户端纯渲染 + atari 提示
//   - 有过手 PASS（双方连过 → 数子终局）
//   - 黑方 = host（先手）

import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/net_engine/relay_v3/relay_device_id.dart';
import '../../../widgets/context_game_colors.dart';
import 'package:xiaodouzi_fr/core/surround_game/board_theme.dart';
import 'package:xiaodouzi_fr/services/lua/lua_game_alias.dart';
import 'package:xiaodouzi_fr/core/game_audio/piece_sound.dart';

import 'go_constants.dart';
import 'go_engine.dart' show
    GoRoom, GoMove, GoBoard, kGoScript, Snapshot, RoomHandle,
    RelayV3Transport, kGoSize;
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart'
    show RelayV3Exception;
import 'go_board.dart' show GoBoardWidget;

// ══════════════════════════════════════════════════════════════
// Lobby Entry Page（单表单：输入昵称 + 房间号，按按钮即尝试加入/创建）
// ══════════════════════════════════════════════════════════════

class LobbyEntryPage extends StatefulWidget {
  const LobbyEntryPage({super.key, required this.onJoined});
  final void Function(RoomHandle) onJoined;
  @override State<LobbyEntryPage> createState() => _LobbyEntryPageState();
}

class _LobbyEntryPageState extends State<LobbyEntryPage> {
  final _aliasCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    LuaGameAlias.load().then((v) {
      if (mounted && v.isNotEmpty && _aliasCtrl.text.isEmpty) {
        setState(() => _aliasCtrl.text = v);
      }
    });
    LuaGameAlias.notifier.addListener(_onAliasChanged);
  }

  void _onAliasChanged() {
    if (!mounted) return;
    final v = LuaGameAlias.value;
    if (v != _aliasCtrl.text) setState(() => _aliasCtrl.text = v);
  }

  @override
  void dispose() {
    LuaGameAlias.notifier.removeListener(_onAliasChanged);
    _aliasCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final alias = _aliasCtrl.text.trim();
    if (alias.isEmpty) { setState(() => _error = '请输入昵称'); return; }
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.length < 4 || code.length > 6) {
      setState(() => _error = '房间码为 4–6 位大写字母数字'); return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final t = RelayV3Transport(
        relayUrl: kGoRelayUrl,
        alias: alias,
        deviceId: await RelayDeviceId.get(),
      );
      await LuaGameAlias.save(alias);
      final h = await t.tryJoinOrCreate(
        code: code,
        script: kGoScript,
        initialParams: {'device_id': t.deviceId, 'alias': alias},
        maxPlayers: 2,
      );
      if (!mounted) return;
      widget.onJoined(h);
    } on RelayV3Exception catch (e) {
      if (!mounted) return;
      final body = e.body.toLowerCase();
      final String msg;
      if (e.statusCode == 409 && body.contains('code collision')) {
        msg = '房间号 $code 已被占用，请换一个';
      } else if (e.statusCode == 409 && body.contains('join rejected')) {
        msg = '房间 $code 已满员，无法加入';
      } else if (e.statusCode == 404) {
        msg = '房间号 $code 不存在且创建失败';
      } else {
        msg = '进入失败（${e.statusCode}）';
      }
      setState(() { _busy = false; _error = msg; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _busy = false; _error = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = BoardTheme.of(context);
    InputDecoration inputDec(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: theme.btnSub.withValues(alpha: 0.6)),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          filled: true,
          fillColor: theme.btnBg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: theme.panelBorder, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: theme.panelBorder, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: theme.btnText, width: 1.6),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _aliasCtrl,
        decoration: inputDec('昵称（如：黑方）'),
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: theme.btnText),
        textAlignVertical: TextAlignVertical.center,
        onChanged: LuaGameAlias.save,
      ),
      SizedBox(height: 12),
      TextField(
        controller: _codeCtrl,
        decoration: inputDec('房间号（4–6 位大写字母数字）'),
        style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.w500, color: theme.btnText,
          letterSpacing: 2, fontFeatures: const [FontFeature.tabularFigures()],
        ),
        keyboardType: TextInputType.text,
        textCapitalization: TextCapitalization.characters,
        maxLength: 6,
        onSubmitted: (_) => _busy ? null : _go(),
      ),
      SizedBox(height: 12),
      Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.btnText.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: EdgeInsets.only(top: 1),
            child: Text('◐', style: TextStyle(color: theme.btnSub, fontSize: 13)),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '输入同一号码即可对战，谁先到谁是黑方（先手）',
              style: TextStyle(color: theme.btnSub, fontSize: 12, height: 1.4),
            ),
          ),
        ]),
      ),
      if (_error != null) ...[
        SizedBox(height: 8),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.error.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: EdgeInsets.only(top: 1),
              child: Text('◉', style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
            ),
            SizedBox(width: 6),
            Expanded(
              child: Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12, height: 1.4)),
            ),
          ]),
        ),
      ],
      SizedBox(height: 20),
      SizedBox(
        width: double.infinity, height: 48,
        child: FilledButton(
          onPressed: _busy ? null : _go,
          style: FilledButton.styleFrom(
            backgroundColor: theme.btnText,
            foregroundColor: theme.panelBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
          child: _busy
              ? SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: theme.panelBg),
                )
              : const Text('进入对局',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 2)),
        ),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════
// Online Game Page
//
// 双方看同一棋盘（无镜像）。落子在交点，点击 → 待确认 → 确认发 MOVE。
// 有过手 PASS。终局：双方连过 → 本地数子 → 双方发 WIN → 服务端比对。
// ══════════════════════════════════════════════════════════════

class OnlineGamePage extends StatefulWidget {
  const OnlineGamePage({super.key, required this.handle, required this.onLeave});
  final RoomHandle handle;
  final Future<void> Function() onLeave;
  @override State<OnlineGamePage> createState() => _OnlineGamePageState();
}

class _OnlineGamePageState extends State<OnlineGamePage> {
  StreamSubscription<Snapshot>? _sub;
  Snapshot? _snap;
  List<GoMove> _moves = const [];
  GoBoard _board = const [];
  bool _ackedLocally = false;
  (int, int)? _pendingPoint;
  bool _winDeclared = false;

  late final GoRoom _room;

  @override
  void initState() {
    super.initState();
    _room = GoRoom(widget.handle);
    _snap = widget.handle.latest;
    _rebuild(_snap);
    _sub = widget.handle.snapshots.listen(_onSnapshot);
    PieceSound.instance.preload();
  }

  void _onSnapshot(Snapshot s) {
    if (!mounted) return;
    final prevMoveCount = _moves.length;
    setState(() { _snap = s; _rebuild(s); });
    if (_moves.length > prevMoveCount) PieceSound.instance.play();
    if (_moves.length != prevMoveCount && _pendingPoint != null) {
      setState(() => _pendingPoint = null);
    }
    if (_ackedLocally && (s.state != 'lobby' && s.state != 'ready')) {
      setState(() => _ackedLocally = false);
    }
    if (s.state == 'lobby' && _winDeclared) _winDeclared = false;
    _maybeRequestEnd();
  }

  void _rebuild(Snapshot? s) {
    _moves = GoRoom.rebuildMoves(s);
    _board = GoRoom.rebuildBoard(_moves);
  }

  /// 最后一个真正的落子坐标（跳过 pass 条目，避免红点误指 (0,0) 角）。
  /// pass 条目的 x/y 是默认 0 —— 若直接把 `_moves.last` 当 lastMove，
  /// 最后一步是过手时红点会错误地落在角落。
  (int, int)? _lastRealMove() {
    for (var i = _moves.length - 1; i >= 0; i--) {
      if (!_moves[i].isPass) return (_moves[i].x, _moves[i].y);
    }
    return null;
  }

  @override
  void dispose() { _sub?.cancel(); super.dispose(); }

  // ── 角色与回合 ──

  bool get _imBlack {
    final blackId = GoRoom.blackPlayerId(_snap);
    if (blackId == null) return false;
    return _room.deviceId == blackId;
  }

  bool get _isMyTurn {
    if (_snap == null) return false;
    final blackTurn = GoRoom.isBlackTurn(_moves);
    return blackTurn == _imBlack;
  }

  bool _canPerform(String action) => GoRoom.canPerform(
        action, _snap, isBlack: _imBlack, isMyTurn: _isMyTurn);

  // ── 网络动作 ──

  Future<void> _ack() async {
    if (_ackedLocally) return;
    setState(() => _ackedLocally = true);
    try { await _room.ack(); } catch (_) {
      if (mounted) setState(() => _ackedLocally = false);
    }
  }

  Future<void> _deal() async => _room.deal();
  Future<void> _reset() async { setState(() => _pendingPoint = null); await _room.reset(); }
  Future<void> _pass() async { setState(() => _pendingPoint = null); await _room.pass(); }

  void _setPending(Offset localPos, double side) {
    if (!_isMyTurn) return;
    if (_snap?.state != 'playing') return;
    final point = _pointFromLocal(localPos, side);
    if (point == null) return;
    final (x, y) = point;
    if (_board[y][x] != 0) return;
    setState(() { _pendingPoint = (_pendingPoint == (x, y)) ? null : (x, y); });
  }

  Future<void> _confirmMove() async {
    final p = _pendingPoint;
    if (p == null) return;
    if (!_isMyTurn) { setState(() => _pendingPoint = null); return; }
    final (x, y) = p;
    if (_board[y][x] != 0) { setState(() => _pendingPoint = null); return; }
    setState(() => _pendingPoint = null);
    await _room.move(GoMove(x: x, y: y, isBlack: _imBlack));
  }

  void _cancelPending() => setState(() => _pendingPoint = null);

  (int, int)? _pointFromLocal(Offset pos, double side) {
    const padding = 16.0;
    final gridSize = side - padding * 2;
    final step = gridSize / (kGoSize - 1);
    final gx = (pos.dx - padding) / step;
    final gy = (pos.dy - padding) / step;
    final x = gx.round();
    final y = gy.round();
    if (x < 0 || x >= kGoSize || y < 0 || y >= kGoSize) return null;
    if ((gx - x).abs() > 0.5 || (gy - y).abs() > 0.5) return null;
    return (x, y);
  }

  /// 双方连过 → state=ended → 本地数子 → 发 WIN。幂等。
  void _maybeRequestEnd() {
    if (_winDeclared) return;
    if (_snap?.state != 'ended') return;
    if (GoRoom.winner(_snap) != null) return;  // 已有终局结果
    if (GoRoom.passes(_snap) < 2) return;
    _winDeclared = true;
    final area = GoRoom.detectArea(_board);
    _room.declareWin(black: area.black, white: area.white);
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
    if (phase == null || phase == 'lobby' || phase == 'ready') {
      return _buildLobby(theme);
    }
    if (phase == 'ended') return _buildFinished(theme);
    return _buildPlaying(theme);
  }

  // ── 阶段：等待对手 + 准备 ──

  Widget _buildLobby(BoardThemeData theme) {
    final code = _snap?.roomCode ?? '------';
    final players = GoRoom.players(_snap);
    final readyMap = GoRoom.readyMap(_snap);
    final myId = _room.deviceId;
    final phase = _snap?.state;
    final bothReady = phase == 'ready';
    final iAmReady = bothReady || _ackedLocally || (readyMap[myId] == true);
    final canDeal = _canPerform('DEAL');
    final title = bothReady ? '双方已就绪' : '等待对手';

    return Scaffold(
      backgroundColor: theme.boardSurface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.panelBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: theme.panelBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
                      blurRadius: 16, offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: EdgeInsets.fromLTRB(28, 28, 28, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(title,
                        style: TextStyle(color: theme.btnText, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 2)),
                    SizedBox(height: 6),
                    Container(width: 24, height: 2, color: theme.btnText),
                    SizedBox(height: 18),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: theme.btnText.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: theme.btnText.withValues(alpha: 0.2), width: 1),
                      ),
                      child: Text(code,
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: 8, color: theme.btnText,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                    ),
                    SizedBox(height: 22),
                    ...players.entries.map((e) {
                      final isMe = e.key == myId;
                      final isReady = readyMap[e.key] == true;
                      return Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Row(children: [
                          _ReadyAvatar(name: e.value, isReady: isReady, color: theme.btnText),
                          SizedBox(width: 14),
                          Expanded(
                            child: Text('${e.value}${isMe ? "  (我)" : ""}',
                              style: TextStyle(color: theme.btnText, fontSize: 15, fontWeight: isMe ? FontWeight.w600 : FontWeight.w500)),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isReady ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12) : theme.btnSub.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(isReady ? '已准备 ✓' : '未准备',
                              style: TextStyle(color: isReady ? Theme.of(context).colorScheme.primary : theme.btnSub, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1)),
                          ),
                        ]),
                      );
                    }),
                    if (players.length < 2) ...[
                      SizedBox(height: 16),
                      Text('把房间号发给朋友', style: TextStyle(color: theme.btnSub, fontSize: 12, height: 1.4)),
                    ],
                    if (players.length >= 2) ...[
                      SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity, height: 48,
                        child: bothReady
                            ? (canDeal
                                ? FilledButton(
                                    onPressed: _deal,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: theme.btnText, foregroundColor: theme.panelBg,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0),
                                    child: const Text('开始游戏 ▸', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 2)))
                                : Center(child: Text('等待房主开始…', style: TextStyle(color: theme.btnSub, fontSize: 13, letterSpacing: 1))))
                            : (iAmReady
                                ? FilledButton(
                                    onPressed: null,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: theme.btnSub.withValues(alpha: 0.4), foregroundColor: theme.panelBg,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0),
                                    child: const Text('已准备 ✓', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 2)))
                                : OutlinedButton(
                                    onPressed: _canPerform('ACK') ? _ack : null,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Theme.of(context).colorScheme.primary,
                                      side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.6),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                    child: const Text('准备好了', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 2)))),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 阶段：对战中 ──

  Widget _buildPlaying(BoardThemeData theme) {
    return Scaffold(
      backgroundColor: theme.boardSurface,
      body: SafeArea(child: Column(children: [
        _buildTurnBar(theme, context),
        Expanded(
          child: Center(child: LayoutBuilder(builder: (context, constraints) {
            final side = constraints.biggest.shortestSide;
            // atari 高亮：本回合方被打吃的对方群（当前回合方要能看出吃子机会）
            final myColor = _imBlack ? 1 : 2;
            final opponent = _imBlack ? 2 : 1;
            final atari = _isMyTurn
                ? GoRoom.groupsInAtari(_board, opponent)
                : GoRoom.groupsInAtari(_board, myColor);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _setPending(d.localPosition, side),
              child: GoBoardWidget(
                board: _board,
                lastMove: _lastRealMove(),
                previewPoint: (_isMyTurn && _pendingPoint != null) ? _pendingPoint : null,
                previewIsBlack: _imBlack,
                atariPoints: atari,
              ),
            );
          })),
        ),
        _buildConfirmSlot(theme, context),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (_canPerform('PASS')) ...[
              _bottomAction(Icons.skip_next, '过手', _pass, theme),
              SizedBox(width: 16),
            ],
            if (_canPerform('RESIGN')) ...[
              _bottomAction(Icons.flag_outlined, '认输', _showResignConfirm, theme),
              SizedBox(width: 16),
            ],
            if (_canPerform('RESET')) ...[
              _bottomAction(Icons.refresh, '重新开始', _reset, theme),
              SizedBox(width: 16),
            ],
            _bottomAction(Icons.exit_to_app, '退出', widget.onLeave, theme),
          ]),
        ),
      ])),
    );
  }

  Widget _buildTurnBar(BoardThemeData theme, BuildContext context) {
    final blackTurn = GoRoom.isBlackTurn(_moves);
    final isMine = blackTurn == _imBlack;
    final gc = context.gameColors;
    final myColor = _imBlack ? gc.pieceBlack : gc.pieceWhite;
    final myLabel = _imBlack ? '黑方' : '白方';
    final turnColor = blackTurn ? gc.pieceBlack : gc.pieceWhite;
    final turnLabel = blackTurn ? '黑方' : '白方';
    final caps = GoRoom.captures(_snap);
    final capsText = ' 黑吃×${caps.white} 白吃×${caps.black}';
    final String statusText;
    if (_pendingPoint != null && isMine) {
      final (px, py) = _pendingPoint!;
      final colLabel = String.fromCharCode('A'.codeUnitAt(0) + px);
      final rowLabel = kGoSize - py;
      statusText = '落子 $colLabel$rowLabel？点别处改点';
    } else {
      statusText = isMine ? '轮到你（$myLabel）落子$capsText' : '等待 $turnLabel 落子…$capsText';
    }
    return SizedBox(
      height: kGoTurnBarHeight, width: double.infinity,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16),
        color: theme.panelBg.withValues(alpha: 0.5),
        alignment: Alignment.center,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 14, color: turnColor),
          SizedBox(width: 8),
          Flexible(
            child: Text(statusText, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.btnText, fontSize: 14, fontWeight: FontWeight.w500)),
          ),
          SizedBox(width: 8),
          Container(width: 12, height: 12,
            decoration: BoxDecoration(color: myColor, shape: BoxShape.circle, border: Border.all(color: theme.panelBorder))),
        ]),
      ),
    );
  }

  Widget _buildConfirmSlot(BoardThemeData theme, BuildContext context) {
    if (_pendingPoint == null) {
      return SizedBox(height: kGoConfirmBarHeight, width: double.infinity);
    }
    final gc = context.gameColors;
    final myColor = _imBlack ? gc.pieceBlack : gc.pieceWhite;
    return SizedBox(
      height: kGoConfirmBarHeight, width: double.infinity,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          OutlinedButton.icon(
            onPressed: _cancelPending,
            icon: Icon(Icons.close, size: 18),
            label: Text('取消'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
              side: BorderSide(color: Theme.of(context).colorScheme.error),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
          ),
          SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: _confirmMove,
            icon: Icon(Icons.check, size: 18, color: Theme.of(context).colorScheme.onPrimary),
            label: Text('确认落子', style: TextStyle(color: Theme.of(context).colorScheme.onPrimary)),
            style: ElevatedButton.styleFrom(
              backgroundColor: myColor,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 10),
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
        SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ]),
    );
  }

  // ── 阶段：终局 ──

  Widget _buildFinished(BoardThemeData theme) {
    final winner = GoRoom.winner(_snap);
    final area = GoRoom.detectArea(_board);
    final isBlackWin = winner == 'black';
    final iWon = (winner == 'draw') ? false : (isBlackWin == _imBlack);
    final msg = winner == 'draw' ? '平局' : (iWon ? '我方获胜！' : '对方获胜');
    final winColor = (winner == 'black')
        ? context.gameColors.pieceBlack
        : (winner == 'white' ? context.gameColors.pieceWhite : Theme.of(context).colorScheme.outline);
    return Scaffold(
      backgroundColor: theme.boardSurface,
      body: SafeArea(child: Stack(children: [
        Center(child: LayoutBuilder(builder: (context, constraints) {
          return GoBoardWidget(
            board: _board,
            lastMove: _lastRealMove(),
          );
        })),
        Container(color: Theme.of(context).colorScheme.scrim, child: Center(child: Container(
          padding: EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          decoration: BoxDecoration(color: theme.panelBg, borderRadius: BorderRadius.circular(16)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.emoji_events, size: 48, color: winColor),
            SizedBox(height: 12),
            Text(msg, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: winColor)),
            SizedBox(height: 8),
            Text('黑 ${area.black} · 白 ${area.white}', style: TextStyle(color: theme.btnSub, fontSize: 13)),
            SizedBox(height: 8),
            Text(winner == 'draw' ? '双方点数相同' : '${winner == "black" ? "黑方" : "白方"}胜',
              style: TextStyle(color: theme.btnSub, fontSize: 13)),
            SizedBox(height: 16),
            if (_canPerform('RESET'))
              OutlinedButton(
                onPressed: _reset,
                style: OutlinedButton.styleFrom(
                  foregroundColor: winColor, side: BorderSide(color: winColor),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
                child: const Text('再来一局'))
            else
              Text('等待房主开始下一局…', style: TextStyle(color: theme.btnSub, fontSize: 13)),
          ]),
        ))),
      ])),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 小组件：圆环头像 + 打勾圆
// ══════════════════════════════════════════════════════════════

class _ReadyAvatar extends StatelessWidget {
  const _ReadyAvatar({required this.name, required this.isReady, required this.color});
  final String name;
  final bool isReady;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return SizedBox(
      width: 44, height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isReady ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12) : Colors.transparent,
              border: Border.all(
                color: isReady ? Theme.of(context).colorScheme.primary : color.withValues(alpha: 0.35),
                width: isReady ? 2.4 : 1.6,
              ),
            ),
          ),
          if (isReady)
            Icon(Icons.check_rounded, size: 22, color: Theme.of(context).colorScheme.primary)
          else
            Text(letter, style: TextStyle(color: color.withValues(alpha: 0.75), fontSize: 16, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
