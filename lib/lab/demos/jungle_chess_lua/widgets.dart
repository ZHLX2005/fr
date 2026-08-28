// lib/lab/demos/jungle_chess_lua/widgets.dart
//
// 斗兽棋 Lua 版 — UI 组件：LobbyEntryPage + OnlineGamePage。
//
// 关键差异（与五子棋对比）：
//   - **棋盘对称翻转**：host 端（top）整体 Transform.flip(flipY: true)，
//     让双方都看到"自己在底部"。
//   - **触摸坐标手动镜像**：Listener 不在 flip 子树 → 在回调里 y → boardH - y。
//   - **确认按钮移出 flip 层**：固定高度 56px，host 端把传入坐标镜像。
//   - **终局消息用角色**：`_imTop == winner` 推"我方/对方"。
//   - **大小写棋谱**：调试 / 教程时用大写=红 / 小写=蓝；运行时棋盘自动判别。
//
// 共享昵称：LuaGameAlias（4 个 Lua 游戏共用）。
//
// 引擎与 Lua：
//   - JungleEngine（纯函数规则引擎，client-side 验证走法）
//   - JungleRoom（Lua 动作封装 + Snapshot 读取）
//   - 服务端权威字段：top_player_id / players / ready / history / winner

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:xiaodouzi_fr/core/jungle_chess/constants/jungle_constants.dart';
import 'package:xiaodouzi_fr/core/jungle_chess/engine/jungle_engine.dart';
import 'package:xiaodouzi_fr/core/jungle_chess/models/game_state.dart';
import 'package:xiaodouzi_fr/core/jungle_chess/models/piece.dart';
import 'package:xiaodouzi_fr/core/jungle_chess/widgets/jungle_board.dart';
import 'package:xiaodouzi_fr/core/jungle_chess/widgets/jungle_board_frame.dart';
import 'package:xiaodouzi_fr/core/jungle_chess/widgets/jungle_player_panel.dart';
import 'package:xiaodouzi_fr/core/jungle_chess/widgets/jungle_touch_controller.dart';
import 'package:xiaodouzi_fr/core/game_audio/piece_sound.dart';
import 'package:xiaodouzi_fr/core/surround_game/board_theme.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_device_id.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_connection_bar.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart'
    show RelayV3Exception;
import 'package:xiaodouzi_fr/services/lua/lua_game_alias.dart';

import 'jungle_constants.dart';
import 'jungle_engine.dart';

// ══════════════════════════════════════════════════════════════
// LobbyEntryPage — 单表单智能匹配（与五子棋共用模式）
// ══════════════════════════════════════════════════════════════

class LobbyEntryPage extends StatefulWidget {
  const LobbyEntryPage({super.key, required this.onJoined});
  final void Function(RoomHandle) onJoined;

  @override
  State<LobbyEntryPage> createState() => _LobbyEntryPageState();
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
    if (alias.isEmpty) {
      setState(() => _error = '请输入昵称');
      return;
    }
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.length < 4 || code.length > 6) {
      setState(() => _error = '房间码为 4–6 位大写字母数字');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = RelayV3Transport(
        relayUrl: kJungleLuaRelayUrl,
        alias: alias,
        deviceId: await RelayDeviceId.get(),
      );
      await LuaGameAlias.save(alias);
      final h = await t.tryJoinOrCreate(
        code: code,
        script: kJungleChessScript,
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
      setState(() {
        _busy = false;
        _error = msg;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = BoardTheme.of(context);
    InputDecoration inputDec(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: theme.btnSub.withValues(alpha: 0.6)),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
      // ── 提示行（浅灰块，左对齐）──
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
              '输入同一号码即可对战，红方（host）先手',
              style: TextStyle(color: theme.btnSub, fontSize: 12, height: 1.4),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 14),

      // ── 昵称 ──
      TextField(
        controller: _aliasCtrl,
        decoration: inputDec('昵称（如：红方 / 蓝方）'),
        style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: theme.btnText),
        textAlignVertical: TextAlignVertical.center,
        onChanged: LuaGameAlias.save,
      ),
      const SizedBox(height: 12),

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

      // ── 错误提示 ──
      if (_error != null) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.error.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text('◉',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(_error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                      height: 1.4)),
            ),
          ]),
        ),
      ],

      const SizedBox(height: 20),

      // ── 主按钮 ──
      SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton(
          onPressed: _busy ? null : _go,
          style: FilledButton.styleFrom(
            backgroundColor: theme.btnText,
            foregroundColor: theme.panelBg,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
          child: _busy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.panelBg,
                  ),
                )
              : const Text('进入对局',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2)),
        ),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════
// OnlineGamePage — 棋盘 + 准备 / 对战 / 终局
// ══════════════════════════════════════════════════════════════

class OnlineGamePage extends StatefulWidget {
  const OnlineGamePage({
    super.key,
    required this.handle,
    required this.onLeave,
  });
  final RoomHandle handle;
  final Future<void> Function() onLeave;

  @override
  State<OnlineGamePage> createState() => _OnlineGamePageState();
}

class _OnlineGamePageState extends State<OnlineGamePage> {
  StreamSubscription<Snapshot>? _sub;
  Snapshot? _snap;
  List<JungleMoveRecord> _history = const [];
  GameState _gameState = JungleEngine.createInitialStateFor(firstTurn: PlayerColor.red);

  /// 本地乐观状态：lobby 阶段点了"准备好了"立即置 true。
  bool _ackedLocally = false;

  /// 已声明过胜利（防死循环：WIN 万一被拒/网络抖动，不重复发导致闪屏）。
  bool _winDeclared = false;

  late final JungleRoom _room;
  late final JungleTouchController _touchController;

  @override
  void initState() {
    super.initState();
    _room = JungleRoom(widget.handle);
    _touchController = JungleTouchController();
    _touchController.onMoveConfirmed = _onLocalMoveConfirmed;
    _snap = widget.handle.latest;
    _rebuild(_snap);
    _sub = widget.handle.snapshots.listen(_onSnapshot);
    // 预加载落子音，消除首次落子的加载延迟
    PieceSound.instance.preload();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _touchController.dispose();
    super.dispose();
  }

  void _onSnapshot(Snapshot s) {
    if (!mounted) return;
    final prevHistoryLen = _history.length;
    setState(() {
      _snap = s;
      _rebuild(s);
    });
    // history 增长 = 有新落子（自己或对方）→ 播放落子音
    if (_history.length > prevHistoryLen) {
      PieceSound.instance.play();
    }
    if (_ackedLocally && (s.state != 'lobby' && s.state != 'ready')) {
      setState(() => _ackedLocally = false);
    }
    if (s.state == 'lobby' && _winDeclared) {
      _winDeclared = false;
    }
    _maybeDeclareWin();
  }

  void _rebuild(Snapshot? s) {
    _history = JungleRoom.rebuildHistory(s);
    _gameState = JungleRoom.rebuildBoard(_history);
  }

  // ── 角色派生（服务端权威字段）──

  /// 我是 top（红方）吗？
  bool get _imTop {
    final topId = JungleRoom.topPlayerId(_snap);
    if (topId == null) return false;
    return _room.deviceId == topId;
  }

  /// 当前是否轮到我走。
  bool get _isMyTurn {
    if (_snap?.state != 'playing') return false;
    final turn = JungleRoom.currentTurnPlayer(_history);
    final myColor = _imTop ? PlayerColor.red : PlayerColor.blue;
    return turn == myColor;
  }

  /// 按钮可点性：读服务端 action_permissions + 自己角色。
  bool _canPerform(String action) => JungleRoom.canPerform(
        action,
        _snap,
        isTop: _imTop,
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
    await _room.reset();
  }

  Future<void> _resign() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('认输'),
        content: const Text('确认认输？此局结束。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('认输')),
        ],
      ),
    );
    if (confirm == true) await _room.resign();
  }

  /// 触摸控制器触发的本地走法 → 直接发网络（不需确认）。
  ///
  /// JungleTouchController 自身已支持两种交互：
  ///   - 点击棋子 → 选中（pieceSelected）→ 再点击目标 → onMoveConfirmed
  ///   - 按住棋子拖动 → 松手在合法目标 → onMoveConfirmed
  /// 这里直接发 MOVE；服务端 Lua 校验权限 + 写入 history。
  void _onLocalMoveConfirmed(Coord from, Coord to) {
    if (!_isMyTurn) return;
    if (_snap?.state != 'playing') return;
    final piece = _gameState.pieces[from.index];
    if (piece == null) return;
    final color = _imTop ? 'red' : 'blue';
    final rec = JungleMoveRecord(
      fromRow: from.row,
      fromCol: from.col,
      toRow: to.row,
      toCol: to.col,
      color: color,
      round: _history.length + 1,
    );
    PieceSound.instance.play();  // 本地立即响（不等服务端回包）
    _room.move(rec);
  }

  /// 胜负判定：history 增长后本地算 → 发 WIN（幂等：state 已 ended 时 Lua 忽略）。
  void _maybeDeclareWin() {
    if (_winDeclared) return;
    if (_snap?.state != 'playing') return;
    final r = JungleRoom.checkWinner(_gameState);
    if (r.winner != null) {
      _winDeclared = true;
      _room.declareWin(r.winner!);
    }
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

  // ── Lobby / Ready 卡片（同一张，按钮三态原地切换）──

  Widget _buildLobby(BoardThemeData theme) {
    final code = _snap?.roomCode ?? '------';
    final players = JungleRoom.players(_snap);
    final readyMap = JungleRoom.readyMap(_snap);
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
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.06),
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
                          fontFeatures:
                              const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),

                    // 玩家头像列表
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
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.12)
                                  : theme.btnSub.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              isReady ? '已准备 ✓' : '未准备',
                              style: TextStyle(
                                color: isReady
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primary
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
                                    child: const Text('开始游戏 ▸',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 2,
                                        )),
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
                                    child: const Text('已准备 ✓',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 2,
                                        )),
                                  )
                                : OutlinedButton(
                                    onPressed:
                                        _canPerform('ACK') ? _ack : null,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                      side: BorderSide(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        width: 1.6,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                    ),
                                    child: const Text('准备好了',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 2,
                                        )),
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

  // ── 对战中 ──

  Widget _buildPlaying(BoardThemeData theme) {
    return Scaffold(
      backgroundColor: theme.boardSurface,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部回合条（固定 44px）
            _buildTurnBar(theme, context),
            // 上方玩家面板（旋转 180°）—— 永远给对面玩家看。
            // host 端（top）：上方玩家是 bottom（蓝），
            // guest 端（bottom）：上方玩家是 top（红）。
            _buildOpponentPanel(theme),
            // 棋盘（中心）+ 镜像翻转
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 7 / 9,
                  child: JungleBoardFrame(
                    child: _buildBoardWithMirror(),
                  ),
                ),
              ),
            ),
            // 下方玩家面板（我方）—— 不旋转
            _buildMyPanel(theme),
            // WS 状态条 + 拉取快照（共享 widget，自带 stream 订阅 + 防双击）
            RelayConnectionBar(handle: widget.handle),
            // 底部操作栏
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_canPerform('RESIGN')) ...[
                    _bottomAction(Icons.flag_outlined, '认输', _resign, theme),
                    const SizedBox(width: 16),
                  ],
                  if (_canPerform('RESET')) ...[
                    _bottomAction(Icons.refresh, '重新开始', _reset, theme),
                    const SizedBox(width: 16),
                  ],
                  _bottomAction(
                      Icons.exit_to_app, '退出', widget.onLeave, theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTurnBar(BoardThemeData theme, BuildContext context) {
    final turn = JungleRoom.currentTurnPlayer(_history);
    final isMine = (turn == PlayerColor.red) == _imTop;
    final myColor = _imTop ? kRedPieceTint : kBluePieceTint;
    final myLabel = _imTop ? '红方' : '蓝方';
    final turnColor = turn == PlayerColor.red ? kRedPieceTint : kBluePieceTint;
    final turnLabel = turn == PlayerColor.red ? '红方' : '蓝方';

    final String statusText;
    statusText = isMine ? '轮到你（$myLabel）走子' : '等待 $turnLabel 走子…';
    return SizedBox(
      height: kJungleLuaTurnBarHeight,
      width: double.infinity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: theme.panelBg.withValues(alpha: 0.5),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 14, color: turnColor),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                statusText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.btnText,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: myColor,
                shape: BoxShape.circle,
                border: Border.all(color: theme.panelBorder),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 棋盘 + 镜像翻转层。
  ///
  /// 关键点（来自 role-aware-board-mirror ref）：
  ///   - 棋盘渲染层包在 `Transform.flip(rotationZ: π)` 内 → 整体翻转 180°
  ///   - JungleBoard 内部的 GestureDetector 已经在 board-local 坐标系工作，
  ///     而 Transform **不影响** 子 widget 自身的 localPosition，
  ///     所以内部触摸回调收到的 row/col 已经是规范坐标 → 不需要外层再镜像
  ///   - 确认按钮 `_buildConfirmSlot` 不在 flip 子树内 → 显示坐标时手工镜像
  ///   - 终局消息用 `_imTop` 推"我方/对方"（不用"上方/下方"）
  Widget _buildBoardWithMirror() {
    final flipY = _imTop;
    final touch = _touchController;
    final gs = _gameState;

    // 触摸层只在 JungleBoard 自己挂载它时才生效：
    //   - JungleBoard 内部 GestureDetector 的 localPosition 已经是 board-local
    //     （不受外层 Transform.flip 影响），因此 row/col 直接是规范坐标。
    //   - 我们不再额外加外层 GestureDetector，避免双触发 + 坐标系错乱。
    final canTouch = _canMountTouchView();

    if (flipY) {
      return Transform(
        alignment: Alignment.center,
        transform: Matrix4.rotationZ(math.pi),
        child: JungleBoard(
          gameState: gs,
          touchController: canTouch ? touch : null,
          onMoveConfirmed: _onLocalMoveConfirmed,
        ),
      );
    }
    return JungleBoard(
      gameState: gs,
      touchController: canTouch ? touch : null,
      onMoveConfirmed: _onLocalMoveConfirmed,
    );
  }

  bool _canMountTouchView() {
    return _snap != null && _snap?.state == 'playing' && _isMyTurn;
  }

  /// 下方玩家面板 —— "我方"。
  Widget _buildMyPanel(BoardThemeData theme) {
    final myColor = _imTop ? PlayerColor.red : PlayerColor.blue;
    final oppColor = _imTop ? PlayerColor.blue : PlayerColor.red;
    final turn = JungleRoom.currentTurnPlayer(_history);
    final finished = _snap?.state == 'ended';
    return JunglePlayerPanel(
      color: myColor,
      rotated: false,
      isCurrent: !finished && turn == myColor,
      aliveCount: _aliveCount(myColor),
      capturedCount: 8 - _aliveCount(oppColor),
    );
  }

  /// 上方玩家面板 —— "对手"。旋转 180°。
  Widget _buildOpponentPanel(BoardThemeData theme) {
    final myColor = _imTop ? PlayerColor.red : PlayerColor.blue;
    final oppColor = _imTop ? PlayerColor.blue : PlayerColor.red;
    final turn = JungleRoom.currentTurnPlayer(_history);
    final finished = _snap?.state == 'ended';
    return JunglePlayerPanel(
      color: oppColor,
      rotated: true,
      isCurrent: !finished && turn == oppColor,
      aliveCount: _aliveCount(oppColor),
      capturedCount: 8 - _aliveCount(myColor),
    );
  }

  int _aliveCount(PlayerColor c) {
    var n = 0;
    for (final p in _gameState.pieces.values) {
      if (p.isAlive && p.color == c) n++;
    }
    return n;
  }

  Widget _bottomAction(IconData icon, String label, VoidCallback? onTap,
      BoardThemeData theme) {
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

  // ── 终局 ──

  Widget _buildFinished(BoardThemeData theme) {
    final winner = JungleRoom.winner(_snap);
    final isRedWin = winner == 'red';
    final iWon = (isRedWin == _imTop);
    final msg = iWon ? '我方获胜！' : '对方获胜';
    final winColor = isRedWin ? kRedPieceTint : kBluePieceTint;
    final reason = _gameState.gameOverReason ?? '';

    return Scaffold(
      backgroundColor: theme.boardSurface,
      body: SafeArea(
        child: Stack(
          children: [
            // 棋盘背景（保留终局棋面，host 端已镜像）
            Center(
              child: AspectRatio(
                aspectRatio: 7 / 9,
                child: JungleBoardFrame(
                  child: _buildBoardWithMirror(),
                ),
              ),
            ),
            Container(
              color: Theme.of(context).colorScheme.scrim,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 28),
                  decoration: BoxDecoration(
                    color: theme.panelBg,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.emoji_events,
                          size: 48, color: winColor),
                      const SizedBox(height: 12),
                      Text(msg,
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: winColor)),
                      if (reason.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(reason,
                            style: TextStyle(
                                color: theme.btnSub, fontSize: 13)),
                      ],
                      const SizedBox(height: 16),
                      if (_canPerform('RESET'))
                        OutlinedButton(
                          onPressed: _reset,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: winColor,
                            side: BorderSide(color: winColor),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24)),
                          ),
                          child: const Text('再来一局'),
                        )
                      else
                        Text('等待房主开始下一局…',
                            style: TextStyle(
                                color: theme.btnSub, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 小组件：圆环头像 + 打勾圆
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
              color: isReady
                  ? Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.12)
                  : Theme.of(context)
                      .colorScheme
                      .surface
                      .withValues(alpha: 0.0),
              border: Border.all(
                color: isReady
                    ? Theme.of(context).colorScheme.primary
                    : color.withValues(alpha: 0.35),
                width: isReady ? 2.4 : 1.6,
              ),
            ),
          ),
          if (isReady)
            Icon(Icons.check_rounded,
                size: 22,
                color: Theme.of(context).colorScheme.primary)
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
