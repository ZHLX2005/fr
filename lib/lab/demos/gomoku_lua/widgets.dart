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
import '../../../core/net_engine/relay_v3/relay_device_id.dart';

import 'constants.dart';
import 'engine.dart' show
    GomokuRoom, GomokuMove, GomokuBoard, kGomokuScript,
    Snapshot, RoomHandle, RelayV3Transport, kGomokuSize;
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart'
    show RelayV3Exception;
import 'board.dart' show GomokuBoardWidget;
import '../../../widgets/context_game_colors.dart';
import 'package:xiaodouzi_fr/core/surround_game/board_theme.dart';
import 'package:xiaodouzi_fr/services/lua/lua_game_alias.dart';
import 'package:xiaodouzi_fr/core/game_audio/piece_sound.dart';

// ══════════════════════════════════════════════════════════════
// Lobby Entry Page（单表单：输入昵称 + 房间码，按按钮即尝试加入/创建）
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

  /// 单表单智能匹配：先按输入的房间码尝试 join；不存在则用此号创建。
  /// 撞号（409）→ 房间已存在（已有别人是房主），提示换个号。
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
        relayUrl: kGomokuRelayUrl,
        alias: alias,
        deviceId: await RelayDeviceId.get(),
      );
      await LuaGameAlias.save(alias);
      final h = await t.tryJoinOrCreate(
        code: code,
        script: kGomokuScript,
        initialParams: {'device_id': t.deviceId, 'alias': alias},
        maxPlayers: 2,
      );
      if (!mounted) return;
      widget.onJoined(h);
    } on RelayV3Exception catch (e) {
      if (!mounted) return;
      // 服务端两种 409：
      //   - "code collision" → 创建撞号（已被别人创建，tryJoinOrCreate 会回退或重试）
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
      // ── 昵称 ──
      TextField(
        controller: _aliasCtrl,
        decoration: inputDec('昵称（如：黑方）'),
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: theme.btnText),
        textAlignVertical: TextAlignVertical.center,
        onChanged: LuaGameAlias.save,
      ),
      SizedBox(height: 12),

      // ── 房间号 ──
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
      SizedBox(height: 12),

      // ── 提示行（浅灰块，左对齐） ──
      Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.btnText.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: EdgeInsets.only(top: 1),
            child: Text('◐',
                style: TextStyle(color: theme.btnSub, fontSize: 13)),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '输入同一号码即可对战，谁先到谁是房主',
              style: TextStyle(color: theme.btnSub, fontSize: 12, height: 1.4),
            ),
          ),
        ]),
      ),

      // ── 错误提示（暖红浅块） ──
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
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12, height: 1.4),
              ),
            ),
          ]),
        ),
      ],

      SizedBox(height: 20),

      // ── 主按钮 ──
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

// ══════════════════════════════════════════════════════════════
// Online Game Page
//
// 双方看同一棋盘（无镜像）。落子在交点，点击直接落子（无需确认按钮，
// 五子棋落子简单，落错了就落错了——如需悔棋未来再加 UNDO）。
// ══════════════════════════════════════════════════════════════

// 五子棋本黑/本白由 context.gameColors.pieceBlack/pieceWhite 派生。

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
    // 预加载落子音，消除首次落子的加载延迟
    PieceSound.instance.preload();
  }

  void _onSnapshot(Snapshot s) {
    if (!mounted) return;
    // 回合切换（落子数变化）→ 清掉待确认状态，防止跨回合残留
    final prevMoveCount = _moves.length;
    setState(() {
      _snap = s;
      _rebuild(s);
    });
    // 棋谱增长 = 有新落子（自己或对方）→ 播放落子音
    if (_moves.length > prevMoveCount) {
      PieceSound.instance.play();
    }
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
    // lobby 与 ready 共用同一张卡片，只切换底部按钮区，避免布局跳跃/缩放
    if (phase == null || phase == 'lobby' || phase == 'ready') {
      return _buildLobby(theme);
    }
    if (phase == 'ended') return _buildFinished(theme);
    return _buildPlaying(theme);
  }

  // ── 阶段：等待对手 + 准备 ──

  Widget _buildLobby(BoardThemeData theme) {
    final code = _snap?.roomCode ?? '------';
    final players = GomokuRoom.players(_snap);
    final readyMap = GomokuRoom.readyMap(_snap);
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
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: EdgeInsets.fromLTRB(28, 28, 28, 28),
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
                    SizedBox(height: 6),
                    Container(width: 24, height: 2, color: theme.btnText),
                    SizedBox(height: 18),

                    // 房间号 chip
                    Container(
                      padding: EdgeInsets.symmetric(
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
                    SizedBox(height: 22),

                    // 玩家头像列表（圆环 + ACK 状态）
                    ...players.entries.map((e) {
                      final isMe = e.key == myId;
                      final isReady = readyMap[e.key] == true;
                      return Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Row(children: [
                          _ReadyAvatar(
                            name: e.value,
                            isReady: isReady,
                            color: theme.btnText,
                          ),
                          SizedBox(width: 14),
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
                            padding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isReady
                                  ? Theme.of(context).colorScheme.primary
                                      .withValues(alpha: 0.12)
                                  : theme.btnSub.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              isReady ? '已准备 ✓' : '未准备',
                              style: TextStyle(
                                color: isReady
                                    ? Theme.of(context).colorScheme.primary
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
                      SizedBox(height: 16),
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
                      SizedBox(height: 22),
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
                                          Theme.of(context).colorScheme.primary,
                                      side: BorderSide(
                                        color: Theme.of(context).colorScheme.primary,
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

  // ── 阶段：对战中 ──

  Widget _buildPlaying(BoardThemeData theme) {
    return Scaffold(
      backgroundColor: theme.boardSurface,
      body: SafeArea(child: Column(children: [
        // 顶部状态条：轮到谁 / 待确认提示
        _buildTurnBar(theme, context),
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
        _buildConfirmSlot(theme, context),
        // 底部操作栏
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
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
    final blackTurn = GomokuRoom.isBlackTurn(_moves);
    final isMine = blackTurn == _imBlack;
    final gc = context.gameColors;
    final myColor = _imBlack ? gc.pieceBlack : gc.pieceWhite;
    final myLabel = _imBlack ? '黑方' : '白方';
    final turnColor = blackTurn ? gc.pieceBlack : gc.pieceWhite;
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
        padding: EdgeInsets.symmetric(horizontal: 16),
        color: theme.panelBg.withValues(alpha: 0.5),
        alignment: Alignment.center,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 14, color: turnColor),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              statusText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.btnText, fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          SizedBox(width: 8),
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
  Widget _buildConfirmSlot(BoardThemeData theme, BuildContext context) {
    if (_pendingPoint == null) {
      return SizedBox(height: kGomokuConfirmBarHeight, width: double.infinity);
    }
    final gc = context.gameColors;
    final myColor = _imBlack ? gc.pieceBlack : gc.pieceWhite;
    return SizedBox(
      height: kGomokuConfirmBarHeight,
      width: double.infinity,
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
            label: Text('确认落子',
                style: TextStyle(color: Theme.of(context).colorScheme.onPrimary)),
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
    final winner = GomokuRoom.winner(_snap);
    final isBlackWin = winner == 'black';
    // 角色感知：winner == 我方颜色 → 我赢
    final iWon = (isBlackWin == _imBlack);
    final msg = iWon ? '我方获胜！' : '对方获胜';
    final winColor = isBlackWin ? context.gameColors.pieceBlack : context.gameColors.pieceWhite;
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
        Container(color: Theme.of(context).colorScheme.scrim, child: Center(child: Container(
          padding: EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          decoration: BoxDecoration(color: theme.panelBg, borderRadius: BorderRadius.circular(16)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.emoji_events, size: 48, color: winColor),
            SizedBox(height: 12),
            Text(msg, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: winColor)),
            SizedBox(height: 8),
            Text('${isBlackWin ? "黑方" : "白方"}连五', style: TextStyle(color: theme.btnSub, fontSize: 13)),
            SizedBox(height: 16),
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

// ══════════════════════════════════════════════════════════════
// 小组件：圆环头像 + 打勾圆
// ══════════════════════════════════════════════════════════════

/// 玩家头像圆环：
/// - 未准备：空心圆环 + 灰描边
/// - 已准备：实心 + 绿色描边变粗 + 中心打勾
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
              color: isReady ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12) : Theme.of(context).colorScheme.surface.withValues(alpha: 0.0),
              border: Border.all(
                color: isReady ? Theme.of(context).colorScheme.primary : color.withValues(alpha: 0.35),
                width: isReady ? 2.4 : 1.6,
              ),
            ),
          ),
          if (isReady)
            Icon(Icons.check_rounded, size: 22, color: Theme.of(context).colorScheme.primary)
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


