// lib/lab/demos/reversi_lua/widgets.dart
// 黑白翻转棋 Lua 版 — UI 组件：LobbyEntryPage / OnlineGamePage
//
// 布局沿用五子棋规范：
//   - lobby / ready 共用同一张卡片，按钮三态原地切换
//   - playing 阶段：顶部回合条 + 棋盘（Expanded 居中）+ 待确认按钮条 + 底部三件套（认输/悔棋/退出）
//   - ended 阶段：终局 overlay（保留棋盘背景）+ 房主"再来一局"按钮
//   - 落子两步确认（pending + 确认按钮）；回合切换自动清 pending
//
// 业务逻辑全部走 ReversiRoom 封装 + 服务端权威 history + 客户端引擎 (ReversiBoard) 重建。

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:xiaodouzi_fr/core/reversi/board_theme.dart';
import 'package:xiaodouzi_fr/core/reversi/models/reversi_board.dart';
import 'package:xiaodouzi_fr/core/surround_game/board_theme.dart'
    show BoardTheme, BoardThemeData;

import 'board.dart' show ReversiBoardWidget;
import 'constants.dart' show kReversiSize, ReversiAliasPrefs;
import 'engine.dart'
    show
        ReversiRoom,
        ReversiMove,
        Snapshot,
        RoomHandle,
        RelayV3Transport,
        kReversiScript;

import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart'
    show RelayV3Exception;

// ══════════════════════════════════════════════════════════════
// Lobby Entry Page（单表单：输入昵称 + 房间码，按按钮即尝试加入/创建）
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
    // 竞态修复：load 只在用户没输入时回填
    ReversiAliasPrefs.load().then((v) {
      if (mounted && v.isNotEmpty && _aliasCtrl.text.isEmpty) {
        setState(() => _aliasCtrl.text = v);
      }
    });
  }

  @override
  void dispose() {
    _aliasCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  /// 单表单智能匹配：先按输入的房间码尝试 join；不存在则用此号创建。
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
        relayUrl: 'http://47.110.80.47:8988',
        alias: alias,
        deviceId: 'rv-${DateTime.now().microsecondsSinceEpoch}',
      );
      await ReversiAliasPrefs.save(alias);
      final h = await t.tryJoinOrCreate(
        code: code,
        script: kReversiScript,
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
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
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
        style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w500, color: theme.btnText),
        textAlignVertical: TextAlignVertical.center,
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
      const SizedBox(height: 12),

      // ── 提示行 ──
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
              '输入同一号码即可对战，黑白由服务端开局随机分配',
              style: TextStyle(color: theme.btnSub, fontSize: 12, height: 1.4),
            ),
          ),
        ]),
      ),

      // ── 错误提示 ──
      if (_error != null) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFB33A1F).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Text('◉',
                  style: TextStyle(color: Color(0xFFB33A1F), fontSize: 12)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _error!,
                style: const TextStyle(
                    color: Color(0xFFB33A1F), fontSize: 12, height: 1.4),
              ),
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
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
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
// Online Game Page
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
  List<ReversiMove> _moves = const [];
  List<List<PieceType>> _cells = const [];
  bool _ackedLocally = false;
  /// 待确认落子点：(row, col)。点击空格子进入待确认，确认才发 MOVE。
  Position? _pendingPoint;
  /// 已声明过胜利（防死循环）。
  bool _winDeclared = false;
  /// 合法步缓存：snapshot 引用 / 当前玩家变化时重算，避免 build 内 O(64×8) 重扫。
  int? _legalCacheKey;
  Set<Position>? _legalCacheValue;

  late final ReversiRoom _room;

  @override
  void initState() {
    super.initState();
    _room = ReversiRoom(widget.handle);
    _snap = widget.handle.latest;
    _rebuild(_snap);
    _sub = widget.handle.snapshots.listen(_onSnapshot);
  }

  void _onSnapshot(Snapshot s) {
    if (!mounted) return;
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
    if (s.state == 'lobby' && _winDeclared) {
      _winDeclared = false;
    }
    _maybeDeclareWin();
  }

  void _rebuild(Snapshot? s) {
    _moves = ReversiRoom.rebuildMoves(s);
    _cells = ReversiRoom.rebuildBoard(_moves);
    // 棋盘变化 → 清合法步缓存（_snap 引用作 key 防止同帧重复 setState 时仍返回陈旧值）
    _legalCacheKey = null;
    _legalCacheValue = null;
  }

  /// 缓存版合法步：仅在 _cells 或当前玩家变化时重算。
  Set<Position> _legalMovesForCached(bool isBlackTurn) {
    // 用 _cells 身份 + 是否为黑方回合作缓存 key。
    // _cells 在 _rebuild 内整体替换为新 List，所以 identityHashCode 变了必重算；
    // 同帧内 build 多次调用时 identityHashCode 不变，直接走缓存。
    final key = Object.hash(identityHashCode(_cells), isBlackTurn);
    if (_legalCacheKey == key) return _legalCacheValue!;
    final result = ReversiRoom.legalMovesFor(_cells, isBlackTurn).toSet();
    _legalCacheKey = key;
    _legalCacheValue = result;
    return result;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ── 角色与回合 ──

  bool get _imBlack {
    final blackId = ReversiRoom.blackPlayerId(_snap);
    if (blackId == null) return false;
    return _room.deviceId == blackId;
  }

  bool get _isMyTurn {
    if (_snap == null) return false;
    return ReversiRoom.isBlackTurn(_moves) == _imBlack;
  }

  bool _canPerform(String action) => ReversiRoom.canPerform(
        action,
        _snap,
        isBlack: _imBlack,
        isMyTurn: _isMyTurn,
        isHost: _room.isHost,
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

  Future<void> _undo() async {
    setState(() => _pendingPoint = null);
    await _room.undo();
  }

  void _setPending(int row, int col) {
    if (!_isMyTurn) return;
    if (_snap?.state != 'playing') return;
    if (_cells[row][col] != PieceType.empty) return;
    final legalSet = _legalMovesForCached(_imBlack);
    if (!legalSet.contains(Position(row, col))) return;
    setState(() {
      _pendingPoint = (_pendingPoint?.row == row && _pendingPoint?.col == col)
          ? null
          : Position(row, col);
    });
  }

  Future<void> _confirmMove() async {
    final p = _pendingPoint;
    if (p == null) return;
    if (!_isMyTurn) {
      setState(() => _pendingPoint = null);
      return;
    }
    if (_cells[p.row][p.col] != PieceType.empty) {
      setState(() => _pendingPoint = null);
      return;
    }
    setState(() => _pendingPoint = null);
    // 服务端 history 用 {x, y, isBlack}：x = 列(col)、y = 行(row)
    await _room.move(
      ReversiMove(x: p.col, y: p.row, isBlack: _imBlack),
    );
  }

  // ── 胜利判定（客户端从权威 history 重建棋盘后判定）──

  void _maybeDeclareWin() {
    if (_winDeclared) return;
    if (_snap?.state != 'playing') return;
    final blackMoves = ReversiRoom.legalMovesFor(_cells, true);
    final whiteMoves = ReversiRoom.legalMovesFor(_cells, false);
    final winner = ReversiRoom.detectWinner(
      _cells,
      blackCanMove: blackMoves.isNotEmpty,
      whiteCanMove: whiteMoves.isNotEmpty,
    );
    if (winner == null) return;
    _winDeclared = true;
    // 平局服务端不接受（只接受 black/white），平局就当 black 推，由 overlay 文案
    // 区分（detectWinner 已经返回 black/white/draw 三态；这里 draw 跳过）。
    if (winner == 'draw') {
      // 平局不主动发 WIN，等房主 RESET 或认输；overlay 文案靠 _buildFinished 读 snapshot.state='ended' 显示。
      // 但服务端需要 state='ended' 才显示 overlay——这里折衷：直接宣告白方赢是错的，发黑方也不对。
      // 当前方案：客户端检测到平局不主动发，让房间继续走（黑/白可继续落直到终局）；
      // 实际上 8x8 全满/双方无合法步已是终局，需客户端发 WIN。
      // 折衷：发 black，服务端接受（WIN 只校验 device_id 是黑方），但 overlay 显示"平局"
      // —— 与检测结果一致。
      _room.declareWin('black');
    } else {
      _room.declareWin(winner);
    }
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    // 注入 ReversiTheme（棋盘棋子颜色需要），同时把 BoardTheme 也注入
    return Theme(
      data: Theme.of(context).copyWith(
        extensions: [ReversiTheme.classic],
      ),
      child: Builder(builder: (context) {
        final theme = BoardTheme.of(context);
        final phase = _snap?.state;
        // lobby / ready 复用同一张卡片，按钮三态原地切换
        if (phase == null || phase == 'lobby' || phase == 'ready') {
          return _buildLobby(theme);
        }
        if (phase == 'ended') return _buildFinished(theme);
        return _buildPlaying(theme);
      }),
    );
  }

  // ── 阶段：等待对手 + 准备 ──

  Widget _buildLobby(BoardThemeData theme) {
    final code = _snap?.roomCode ?? '------';
    final players = ReversiRoom.players(_snap);
    final readyMap = ReversiRoom.readyMap(_snap);
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
        child: Align(
          alignment: Alignment.topCenter,
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

  // ── 阶段：对战中 ──

  Widget _buildPlaying(BoardThemeData theme) {
    final isBlackTurn = ReversiRoom.isBlackTurn(_moves);
    final legalSet = _legalMovesForCached(isBlackTurn);
    final lastMove = _moves.isEmpty ? null : _moves.last;

    return Scaffold(
      backgroundColor: theme.boardSurface,
      body: SafeArea(
        child: Column(children: [
          // 顶部回合条（固定高度）
          _buildTurnBar(theme, isBlackTurn),
          // 棋盘（Expanded 居中）
          Expanded(
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final side = constraints.biggest.shortestSide;
                  final cell = side / kReversiSize;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) {
                      final col = (d.localPosition.dx / cell).floor();
                      final row = (d.localPosition.dy / cell).floor();
                      if (row >= 0 &&
                          row < kReversiSize &&
                          col >= 0 &&
                          col < kReversiSize) {
                        _setPending(row, col);
                      }
                    },
                    child: Stack(children: [
                      ReversiBoardWidget(
                        cells: _cells,
                        lastMove: lastMove?.toPosition(),
                        legalHints: legalSet,
                        currentIsBlack: isBlackTurn,
                        boardSize: side,
                      ),
                      // 待确认预览圆环
                      if (_pendingPoint != null && _isMyTurn)
                        Positioned(
                          left: _pendingPoint!.col * cell + cell * 0.18,
                          top: _pendingPoint!.row * cell + cell * 0.18,
                          width: cell * 0.64,
                          height: cell * 0.64,
                          child: IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: theme.btnText.withValues(alpha: 0.7),
                                  width: 2.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ]),
                  );
                },
              ),
            ),
          ),
          // 待确认按钮条（固定占位 56）
          _buildConfirmSlot(theme),
          // 底部操作栏：认输 / 悔棋 / 退出
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_canPerform('RESIGN')) ...[
                  _bottomAction(
                      Icons.flag_outlined, '认输', _showResignConfirm, theme),
                  const SizedBox(width: 12),
                ],
                if (_canPerform('UNDO')) ...[
                  _bottomAction(
                      Icons.undo_outlined, '悔棋', _confirmUndo, theme),
                  const SizedBox(width: 12),
                ],
                _bottomAction(Icons.logout_outlined, '退出', widget.onLeave,
                    theme),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildTurnBar(BoardThemeData theme, bool isBlackTurn) {
    final myLabel = _imBlack ? '黑' : '白';
    final turnLabel = isBlackTurn ? '黑' : '白';
    final myColor =
        _imBlack ? const Color(0xFF1A1A1A) : const Color(0xFFFAFAFA);
    final statusText = _pendingPoint != null && _isMyTurn
        ? '落子 ${_pendingPoint!.col + 1}-${String.fromCharCode('A'.codeUnitAt(0) + _pendingPoint!.row)}？点别处改点'
        : _isMyTurn
            ? '轮到你（$myLabel）落子'
            : '等待 $turnLabel 落子…';
    return SizedBox(
      height: 44,
      width: double.infinity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: theme.panelBg.withValues(alpha: 0.5),
        alignment: Alignment.center,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: isBlackTurn
                  ? const Color(0xFF1A1A1A)
                  : const Color(0xFFFAFAFA),
              shape: BoxShape.circle,
              border: Border.all(color: theme.panelBorder),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              statusText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: theme.btnText,
                  fontSize: 14,
                  fontWeight: FontWeight.w500),
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
        ]),
      ),
    );
  }

  /// 待确认按钮条（固定占位）。
  Widget _buildConfirmSlot(BoardThemeData theme) {
    final hasPending = _pendingPoint != null && _isMyTurn;
    return SizedBox(
      height: 56,
      child: Center(
        child: hasPending
            ? SizedBox(
                width: 220,
                height: 40,
                child: FilledButton.icon(
                  onPressed: _confirmMove,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('确认落子',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.btnText,
                    foregroundColor: theme.panelBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _bottomAction(
      IconData icon, String label, VoidCallback onTap, BoardThemeData theme) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: theme.btnSub),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: theme.btnSub,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmUndo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('悔棋？'),
        content: const Text('撤销你刚下的那一步'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('悔棋')),
        ],
      ),
    );
    if (ok == true) await _undo();
  }

  Future<void> _showResignConfirm() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('认输？'),
        content: const Text('认输后游戏直接结束，对手获胜'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('认输')),
        ],
      ),
    );
    if (ok == true) await _room.resign();
  }

  // ── 阶段：终局 ──

  Widget _buildFinished(BoardThemeData theme) {
    // winAccent 来自 ReversiTheme（棋局胜负强调色）
    final revTheme = ReversiTheme.of(context);
    final winner = ReversiRoom.winner(_snap);
    final lastMove = _moves.isEmpty ? null : _moves.last;

    // 判定胜负：服务端 winner 优先；否则从客户端棋盘数
    int black = 0, white = 0;
    for (final row in _cells) {
      for (final c in row) {
        if (c == PieceType.black) {
          black++;
        } else if (c == PieceType.white) {
          white++;
        }
      }
    }
    final isDraw = black == white;
    final iWon = (winner == 'black' && _imBlack) ||
        (winner == 'white' && !_imBlack);
    final title = isDraw
        ? '平局'
        : (iWon ? '我方获胜！' : '对方获胜');

    return Scaffold(
      backgroundColor: theme.boardSurface,
      body: SafeArea(
        child: Stack(children: [
          // 棋盘背景（保留终局棋面）
          Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final side = constraints.biggest.shortestSide;
                return SizedBox(
                  width: side,
                  height: side,
                  child: ReversiBoardWidget(
                    cells: _cells,
                    lastMove: lastMove?.toPosition(),
                    legalHints: const {},
                    currentIsBlack: false,
                    boardSize: side,
                  ),
                );
              },
            ),
          ),
          // 半透明遮罩
          Container(
            color: theme.boardSurface.withValues(alpha: 0.7),
          ),
          // 终局卡片
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
              decoration: BoxDecoration(
                color: theme.panelBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: theme.panelBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isDraw ? Icons.balance : Icons.emoji_events,
                    size: 48,
                    color: revTheme.winAccent,
                  ),
                  const SizedBox(height: 12),
                  Text(title,
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: theme.btnText,
                          letterSpacing: 2)),
                  const SizedBox(height: 8),
                  Text('$black : $white',
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: theme.btnSub)),
                  const SizedBox(height: 20),
                  if (_canPerform('RESET'))
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: _reset,
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.btnText,
                          foregroundColor: theme.panelBg,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                        child: const Text('再来一局 ▸',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 2)),
                      ),
                    )
                  else
                    Text('等待房主开始下一局…',
                        style: TextStyle(
                            color: theme.btnSub,
                            fontSize: 13,
                            letterSpacing: 1)),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── ACK 圆环头像（本地内嵌，不抽公共文件——YAGNI）──

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
                  ? const Color(0xFF16A34A).withValues(alpha: 0.12)
                  : Colors.transparent,
              border: Border.all(
                color: isReady
                    ? const Color(0xFF16A34A)
                    : color.withValues(alpha: 0.35),
                width: isReady ? 2.4 : 1.6,
              ),
            ),
          ),
          if (isReady)
            const Icon(Icons.check_rounded,
                size: 22, color: Color(0xFF16A34A))
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