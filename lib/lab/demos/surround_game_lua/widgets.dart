// lib/lab/demos/surround_game_lua/widgets.dart
// 围追堵截 Lua 版 — UI 组件：LobbyEntryPage / OnlineGamePage
//
// 按 versus-game-room-template 标准（v2026-07-26）与 gomoku_lua 对齐：
//   - 单表单智能匹配（无建房/加入二选一）：昵称 + 房间号 → tryJoinOrCreate
//   - lobby / ready 同一张卡片，底部按钮三态原地切换
//   - 卡片外观统一（圆角 20 + 微阴影 + 1px 边框）
//
// 围追堵截特有的**镜像逻辑**（top_player_id / Transform.flip / 触摸坐标镜像）
// 保留不动，业务规则（走子/放墙/胜负/悔棋）零改动。

import 'dart:async';

import 'package:flutter/material.dart';

import 'constants.dart';
import 'engine.dart' show SgRoom, QuoridorEngine, GameState, MoveRecord,
    GameStatus, Snapshot, RoomHandle, RelayV3Transport, kSurroundGameScript;
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart'
    show RelayV3Exception;
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
import 'package:xiaodouzi_fr/services/lua/lua_game_alias.dart';

// ══════════════════════════════════════════════════════════════
// Lobby Entry Page（单表单：输入昵称 + 房间码，按按钮即尝试加入/创建）
// ══════════════════════════════════════════════════════════════

class LobbyEntryPage extends StatefulWidget {
  const LobbyEntryPage({super.key, required this.onJoined});
  /// 回调：进入房间成功后调用。isHostSide = 我是不是这次创建的房间。
  final void Function(RoomHandle handle, bool isHostSide) onJoined;
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
    // 共享昵称（4 个 Lua 游戏通用）：load 回填 + 监听实时同步
    LuaGameAlias.load().then((v) {
      if (mounted && v.isNotEmpty && _aliasCtrl.text.isEmpty) {
        setState(() => _aliasCtrl.text = v);
      }
    });
    LuaGameAlias.notifier.addListener(_onAliasChanged);
  }

  /// 跨游戏昵称同步：别处改了昵称 → 实时回填到本页输入框。
  void _onAliasChanged() {
    if (!mounted) return;
    final v = LuaGameAlias.value;
    if (v != _aliasCtrl.text) {
      setState(() => _aliasCtrl.text = v);
    }
  }

  @override
  void dispose() {
    LuaGameAlias.notifier.removeListener(_onAliasChanged);
    _aliasCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  /// 单表单智能匹配：按房间号 join；不存在则用此号创建。
  /// 409 code collision → 撞号提示换号；409 join rejected → 已满员。
  Future<void> _go() async {
    final alias = _aliasCtrl.text.trim();
    if (alias.isEmpty) {
      setState(() => _error = '请输入昵称');
      return;
    }
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.length < 4 || code.length > 6) {
      setState(() => _error = '房间码为 4–6 位大写字母数字');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final t = RelayV3Transport(
        relayUrl: kSgRelayUrl,
        alias: alias,
        deviceId: 'sg-p-${DateTime.now().microsecondsSinceEpoch}',
      );
      await LuaGameAlias.save(alias);
      // tryJoinOrCreate 内部：先 join，404 则用此 code 作 requested_code 创建。
      // 我们分不清最终走的是哪个分支——但可以用 snapshot.host_id == deviceId 判定。
      final h = await t.tryJoinOrCreate(
        code: code,
        script: kSurroundGameScript,
        initialParams: {'device_id': t.deviceId, 'alias': alias},
        maxPlayers: 2,
      );
      if (!mounted) return;
      // 判定 host 端：snapshot 的 host_id 等于我的 deviceId ⇒ 我是本次创建者
      final hostId = SgRoom.hostId(h.latest);
      final isHostSide = hostId != null && hostId == t.deviceId;
      widget.onJoined(h, isHostSide);
    } on RelayV3Exception catch (e) {
      if (!mounted) return;
      // 服务端两种 409：
      //   - "code collision" → 撞号（别人已建同号）
      //   - "join rejected"  → 房间已满（rejected_join 触发）
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
    // 圆角浅底输入框（聚焦时边框变粗变深）
    InputDecoration inputDec(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: theme.btnSub.withValues(alpha: 0.6)),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
        decoration: inputDec('昵称（如：红方）'),
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: theme.btnText),
        textAlignVertical: TextAlignVertical.center,
        onChanged: LuaGameAlias.save,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _codeCtrl,
        decoration: inputDec('房间号（4–6 位大写字母数字）'),
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: theme.btnText,
          letterSpacing: 2,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        keyboardType: TextInputType.text,
        textCapitalization: TextCapitalization.characters,
        maxLength: 6,
        onSubmitted: (_) => _busy ? null : _go(),
      ),
      const SizedBox(height: 12),

      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.btnText.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text('◐',
                style: TextStyle(color: theme.btnSub, fontSize: 13)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '输入同一号码即可对战，谁先到谁是房主',
              style: TextStyle(color: theme.btnSub, fontSize: 12, height: 1.4),
            ),
          ),
        ]),
      ),

      if (_error != null) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _warnColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Text('◉', style: TextStyle(color: _warnColor, fontSize: 12)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _error!,
                style: const TextStyle(color: _warnColor, fontSize: 12, height: 1.4),
              ),
            ),
          ]),
        ),
      ],

      const SizedBox(height: 20),

      SizedBox(
        width: double.infinity,
        height: 48,
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
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.panelBg,
                  ),
                )
              : const Text('进入对局',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 2)),
        ),
      ),
    ]);
  }
}

// 暖红色（错误提示，避免纯红）
const Color _warnColor = Color(0xFFB33A1F);

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
  final TouchController _touchCtrl = TouchController();  // 首次初始化后不再重建；host 端在坐标回调里镜像
  String? _lastUndoRequester;
  /// 本地乐观状态：lobby 阶段点了"准备好了"立即置 true，不等服务端回包。
  /// 离开 lobby（→ ready/playing/ended）时清除。
  bool _ackedLocally = false;
  /// 已声明过胜利（防死循环：WIN 万一被拒/网络抖动，不重复发导致闪屏）。
  /// RESET/新局开始时重置。
  bool _winDeclared = false;

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
    // 离开 lobby/ready 阶段 → 清除本地 ACK 乐观标记
    if (_ackedLocally && (s.state != 'lobby' && s.state != 'ready')) {
      setState(() => _ackedLocally = false);
    }
    // RESET 回到 lobby → 新局开始，重置胜利声明标志
    if (s.state == 'lobby' && _winDeclared) {
      _winDeclared = false;
    }
    // 胜利检测：本地 QuoridorEngine 从权威 history 重建出 gs.status != running，
    // 但 Lua state 还在 playing（Lua 没有引擎，无法自行判胜）→ 发 WIN 让服务端记 ended+winner。
    // _winDeclared 防死循环：WIN 万一被拒/网络抖动，不重复发导致闪屏。
    _maybeDeclareWin();
    _maybeShowUndoIncomingDialog();
  }

  /// 某方走到终点 / 平局时，向服务端声明胜利。
  void _maybeDeclareWin() {
    if (_winDeclared) return;
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
    _winDeclared = true;
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
  bool get _imTop {
    final topId = SgRoom.topPlayerId(_snap);
    if (topId == null) return false;
    return _room.deviceId == topId;
  }

  /// 当前回合是否轮到自己
  bool get _isMyTurn {
    if (_snap == null) return false;
    return _imTop == _gs.currentPlayerIsTop;
  }

  /// ★按钮可点性的单一入口：读服务端 action_permissions + 自己角色判定。
  bool _canPerform(String action) {
    final justMovedByMe = _isMyTurn ? false
        : SgRoom.canRequestUndo(_snap, _gs, _room.deviceId);
    return SgRoom.canPerform(
      action, _snap,
      isHost: _room.isHost,
      isMyTurn: _isMyTurn,
      isUndoRequester: _room.deviceId == SgRoom.undoRequester(_snap),
      justMovedByMe: justMovedByMe,
    );
  }

  bool _validateWall(int wx, int wy, WallOrientation o) {
    return QuoridorEngine.isWallPlacementValid(
      _gs.wallGrid, _gs.adjacency, _gs.topPlayerId, _gs.bottomPlayerId,
      wx, wy, o,
    );
  }

  // ── 触摸 ──

  Offset _canonicalLocalPosition(Offset pos) =>
      _flipY ? Offset(pos.dx, _boardSizePx - pos.dy) : pos;

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
    // lobby 与 ready 共用同一张卡片，只切换底部按钮区，避免布局跳跃
    if (phase == null || phase == 'lobby' || phase == 'ready') {
      return _buildLobby(theme);
    }
    if (phase == 'ended') return _buildFinished(theme);
    return _buildPlaying(theme);
  }

  // ── 阶段：等待对手 + 准备（合并 lobby/ready，底部按钮三态原地切换） ──

  Widget _buildLobby(BoardThemeData theme) {
    final code = _snap?.roomCode ?? '------';
    final players = SgRoom.players(_snap);
    final readyMap = SgRoom.readyMap(_snap);
    final myId = _room.deviceId;
    final phase = _snap?.state;
    final bothReady = phase == 'ready';
    final iAmReady =
        bothReady || _ackedLocally || (readyMap[myId] == true);
    final canDeal = _canPerform('DEAL');
    final title = bothReady ? '双方已就绪' : '等待对手';

    return Scaffold(
      backgroundColor: theme.boardSurface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.panelBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: theme.panelBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(title,
                        style: TextStyle(
                          color: theme.btnText,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        )),
                    const SizedBox(height: 6),
                    Container(width: 24, height: 2, color: theme.btnText),
                    const SizedBox(height: 18),

                    // 房间号 chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: theme.btnText.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: theme.btnText.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        code,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 8,
                          color: theme.btnText,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),

                    // 玩家头像列表（圆环 + ACK 状态）
                    ...players.entries.map((e) {
                      final isMe = e.key == myId;
                      final isReady = readyMap[e.key] == true;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(children: [
                          _ReadyAvatar(
                            name: e.value,
                            isReady: isReady,
                            color: theme.btnText,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              '${e.value}${isMe ? "  (我)" : ""}',
                              style: TextStyle(
                                color: theme.btnText,
                                fontSize: 15,
                                fontWeight: isMe
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isReady
                                  ? const Color(0xFF16A34A)
                                      .withValues(alpha: 0.12)
                                  : theme.btnSub.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              isReady ? '已准备 ✓' : '未准备',
                              style: TextStyle(
                                color: isReady
                                    ? const Color(0xFF16A34A)
                                    : theme.btnSub,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ]),
                      );
                    }),

                    if (players.length < 2) ...[
                      const SizedBox(height: 16),
                      Text(
                        '把房间号发给朋友',
                        style: TextStyle(
                          color: theme.btnSub,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],

                    if (players.length >= 2) ...[
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: bothReady
                            ? (canDeal
                                ? FilledButton(
                                    onPressed: _deal,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: theme.btnText,
                                      foregroundColor: theme.panelBg,
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      elevation: 0,
                                    ),
                                    child: const Text(
                                      '开始游戏 ▸',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                  )
                                : Center(
                                    child: Text(
                                      '等待房主开始…',
                                      style: TextStyle(
                                        color: theme.btnSub,
                                        fontSize: 13,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ))
                            : (iAmReady
                                ? FilledButton(
                                    onPressed: null,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: theme.btnSub
                                          .withValues(alpha: 0.4),
                                      foregroundColor: theme.panelBg,
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      elevation: 0,
                                    ),
                                    child: const Text(
                                      '已准备 ✓',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                  )
                                : OutlinedButton(
                                    onPressed:
                                        _canPerform('ACK') ? _ack : null,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor:
                                          const Color(0xFF16A34A),
                                      side: const BorderSide(
                                        color: Color(0xFF16A34A),
                                        width: 1.6,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                    ),
                                    child: const Text(
                                      '准备好了',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                  )),
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

  // ── 阶段：游戏中（LAN 风格单面板） ──

  Widget _buildPlaying(BoardThemeData theme) {
    final gs = _gs;
    final isRunning = gs.status == GameStatus.running;
    final canMountTouchView = _snap != null
        && _snap?.state == 'playing'
        && _canPerform('MOVE');
    return Scaffold(
      backgroundColor: theme.boardSurface,
      body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cs = w / 11;
        final boardSize = w;
        _boardSizePx = boardSize;
        _ensureTouchController(boardSize);

        return Column(children: [
          Expanded(
            child: Center(child: SizedBox(
              width: boardSize, height: boardSize,
              child: Stack(clipBehavior: Clip.none, children: [
                if (_flipY)
                  Transform.flip(flipY: true, child: _drawLayer(cs, boardSize, theme))
                else
                  _drawLayer(cs, boardSize, theme),
                _buildConfirmActions(cs, boardSize, theme),
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
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 6),
            child: Center(child: _buildPlayerPanel(theme)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (isRunning && _canPerform('RESIGN')) ...[
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
        ]);
      })),
    );
  }

  void _ensureTouchController(double boardSize) {
    // TouchController 已在字段初始化时创建；这里保留占位以兼容旧调用点，
    // 未来若需要"按棋盘大小重建"再在此处 rebuild。
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

    final dragOffset = toc.targetCellId != null ? toc.dragOffset : null;

    return Stack(clipBehavior: Clip.none, children: [
      ChessBoard(cellSize: cs, theme: theme),
      ChessWall(history: gs.history, cellSize: cs, theme: theme),
      PlayerPrompt(validMoves: gs.validMoves, cellSize: cs, theme: theme,
          visible: toc.targetCellId != null),
      ChessPlayer(cellId: topId, cellSize: cs, color: theme.piecePlayerA,
          dragOffset: gs.currentPlayerIsTop ? dragOffset : null),
      ChessPlayer(cellId: bottomId, cellSize: cs, color: theme.piecePlayerB,
          dragOffset: gs.currentPlayerIsTop ? null : dragOffset),
      if (pendingCellId != null)
        _PendingHighlight(cellId: pendingCellId, cellSize: cs, theme: theme),
      WallPrompt(wallData: toc.previewWall ?? toc.pendingWall,
          cellSize: cs, theme: theme,
          isValid: toc.wallPreviewValid,
          visible: toc.previewWall != null || toc.pendingWall != null),
    ]);
  }

  Widget _buildConfirmActions(double cs, double boardSize, BoardThemeData theme) {
    final toc = _touchCtrl;
    int? visualCellId = toc.pendingTargetCellId;
    ({int x, int y, WallOrientation o})? visualWall = toc.pendingWall;
    if (_flipY) {
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
    final myIsTop = _imTop;
    final active = isRunning && myIsTop == gs.currentPlayerIsTop;
    final toc = _touchCtrl;
    final steps = gs.history.where((m) => !m.isWall && m.isTopPlayer == myIsTop).length;
    final walls = myIsTop ? gs.topWallsPlaced : gs.bottomWallsPlaced;
    final canUndo = _canPerform('UNDO_REQUEST');
    return PlayerPanel(
      rotated: false,
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
    final w = SgRoom.winner(_snap);
    final isTopWin = w == 'top' || (w == null && gs.status == GameStatus.topWin);
    final isDraw = w == null && gs.status == GameStatus.draw;
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

// ══════════════════════════════════════════════════════════════
// 小组件：圆环头像 + 打勾圆（从 gomoku_lua/widgets.dart 内嵌复用；
// YAGNI：等第 3 个 versus demo 出现时再抽公共文件）
// ══════════════════════════════════════════════════════════════

class _ReadyAvatar extends StatelessWidget {
  const _ReadyAvatar({
    required this.name,
    required this.isReady,
    required this.color,
  });

  final String name;
  final bool isReady;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isReady ? const Color(0xFF16A34A).withValues(alpha: 0.12) : Colors.transparent,
              border: Border.all(
                color: isReady ? const Color(0xFF16A34A) : color.withValues(alpha: 0.35),
                width: isReady ? 2.4 : 1.6,
              ),
            ),
          ),
          if (isReady)
            const Icon(Icons.check_rounded, size: 22, color: Color(0xFF16A34A))
          else
            Text(
              letter,
              style: TextStyle(
                color: color.withValues(alpha: 0.75),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}
