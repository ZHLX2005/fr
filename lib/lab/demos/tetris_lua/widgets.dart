// lib/lab/demos/tetris_lua/widgets.dart
// 俄罗斯方块 Lua 版 — UI：OnlineGamePage
//
// 入口（LobbyEntryPage）已迁移到 GameLobbyPage +
// kTetrisLobbySpec（lib/core/tetris/lobby/tetris_lobby_spec.dart）。
//
// playing 内核（本地实时非回合制）完全保留不动。
//
// 颜色策略（v6.2）：vs-room 模板的对话框 Toast / 警示色（_warnColor = scheme.error 派生的朱红）/
// 就绪色（#16A34A 绿）/ 遮罩色（Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54)/white70 等）是 versus-game-room 模板
// 的"独立暗色游戏场景"设计决策 —— 切到 zen 米底主题时对战房间仍保持深色 + 警示色更清晰，
// 与通用主题策略（context.colors）解耦。该设计同时被 reversi_lua/widgets.dart 与
// surround_game_lua/widgets.dart 共享，改造需保持模板统一性，因此保留硬编码。

import 'dart:async';
import 'dart:ui' as ui show Gradient;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'engine.dart';
import 'board.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart'
    show WSCloseEvent;
import 'package:xiaodouzi_fr/core/surround_game/board_theme.dart';

/// 断线重连连续失败的判定次数（join 失败按 0.5s·2^n 退避重试）
const int kMaxRecoverAttempts = 5;

// ════════════════════════════════════════════════════════════════════
// Cyber v2 主题令牌（proto-3-cyber-v2 落地）
//
// 替换 _buildPlaying 内部使用的 ColorScheme / kTetrisAccent 系列硬编码，
// 改用赛博朋克配色 + neon 边框 + CRT 方括号 + 扫描线。Lobby / Finished
// 不受影响（继续走 BoardTheme），只覆盖 playing 这一屏。
// ════════════════════════════════════════════════════════════════════
const Color _cBg = Color(0xFF0B0D11);
const Color _cPanel = Color(0xFF11141A);
const Color _cLine = Color(0x3800E5FF); // neon cyan @ 22%
const Color _cLineStrong = Color(0x8C00E5FF); // neon cyan @ 55%
const Color _cNeon = Color(0xFF00E5FF);
const Color _cNeon2 = Color(0xFFFF2BD6); // hard drop accent
const Color _cInk = Color(0xFFDCE3EC);
const Color _cInkSub = Color(0x8CDCE3EC);
const Color _cInkFaint = Color(0x47DCE3EC);
const Color _cScanline = Color(0x14000000);
const Color _cDeltaUp = Color(0xFF3DD68C); // proto .delta.up 绿
const Color _cDeltaDown = Color(0xFFFF5A7A); // proto .delta.down 红（与 piece-Z 同值，已 GG pill 复用）
const Color _cTitleGlow = Color(0x9900E5FF); // proto title-glow rgba(0,229,255,0.6)

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
  late final TetrisRoom _room;

  // 本地游戏态（playing 阶段才创建）
  TetrisEngine? _engine;
  Timer? _gravityTimer;
  Timer? _repeatTimer; // 长按左/右/软降的重复触发

  bool _ackedLocally = false; // lobby 乐观
  bool _bustDeclared = false; // 防止 LOSE 重发
  DateTime? _lastSyncAt; // SYNC 节流
  int? _lastOppScore; // 对手上个快照的分数（delta 计算基准）
  int? _oppDelta; // 对手最近一次分数变化；null = 不显示徽章

  // 断线恢复态：WS 断开 → 终止本地游戏（暂停）→ rejoin 重连 → 恢复
  StreamSubscription<WSCloseEvent>? _closeSub;
  bool _disconnected = false; // WS 断开中
  bool _recoverFailed = false; // 重连连续失败 → 提示离开
  int _recoverAttempts = 0;
  Timer? _recoverTimer;

  @override
  void initState() {
    super.initState();
    _room = TetrisRoom(widget.handle);
    _snap = widget.handle.latest;
    _sub = widget.handle.snapshots.listen(_onSnapshot);
    _closeSub = widget.handle.closeEvents.listen(_onDisconnect);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _closeSub?.cancel();
    _recoverTimer?.cancel();
    _gravityTimer?.cancel();
    _repeatTimer?.cancel();
    _engine?.dispose();
    super.dispose();
  }

  void _onSnapshot(Snapshot s) {
    if (!mounted) return;
    _trackOppDelta(s);
    setState(() => _snap = s);

    // 断线恢复：自己重新出现在 players（rejoin 成功 / WS 重连拿到新鲜快照）
    // → 结束断开态，恢复本地游戏并重报 state（断连期间 states 可能被清）。
    if (_disconnected) {
      if (TetrisRoom.players(s)[_room.deviceId] == null) {
        return; // 还没恢复（自己尚未回到房间），等下一次快照
      }
      _recoverTimer?.cancel();
      _recoverTimer = null;
      _recoverAttempts = 0;
      setState(() {
        _disconnected = false;
        _recoverFailed = false;
      });
      if (s.state == 'playing') {
        _ensureEngine();
        _lastSyncAt = null; // 强制重报，把当前棋盘重新填回 states
        _syncNow();
        _scheduleGravity();
      }
    }

    final phase = s.state;
    if (phase == 'playing') {
      _ensureEngine();
    } else {
      // 离开 playing（RESET 回 lobby / 终局 ended）→ 回收本地游戏态
      if (_engine != null) _teardownEngine();
    }
    if (phase == 'lobby') {
      // 新一局：清乐观/胜负标志
      _ackedLocally = false;
      _bustDeclared = false;
      _lastOppScore = null;
      _oppDelta = null;
    }
    if (_ackedLocally && phase != 'lobby' && phase != 'ready') {
      _ackedLocally = false;
    }
  }

  /// 记录对手分数变化 → delta 徽章数据（proto .opp .delta.up / .down）。
  /// 首帧或分数未变 → null（不显示，避免原型里没有的常驻假徽章）。
  void _trackOppDelta(Snapshot s) {
    final oppId = TetrisRoom.opponentId(s, _room.deviceId);
    final opp = oppId == null ? null : TetrisRoom.stateOf(s, oppId);
    if (opp == null) {
      _lastOppScore = null;
      _oppDelta = null;
      return;
    }
    final last = _lastOppScore;
    _oppDelta = (last == null || opp.score == last) ? null : opp.score - last;
    _lastOppScore = opp.score;
  }

  /// WS 断开：终止本地游戏（暂停重力/输入、保留棋盘与分数），
  /// 并尝试重连，避免盲玩导致双方脱节。
  void _onDisconnect(WSCloseEvent event) {
    if (!mounted || _disconnected) return;
    _gravityTimer?.cancel();
    _gravityTimer = null;
    _repeatTimer?.cancel();
    _repeatTimer = null;
    setState(() {
      _disconnected = true;
      _recoverFailed = false;
    });
    _recoverAttempts = 0;
    _recover();
  }

  /// 重连：rejoin 重新注册 sub + 连 WS。join 失败（瞬时断网）指数退避重试，
  /// 连续 [kMaxRecoverAttempts] 次仍失败 → 提示离开。
  Future<void> _recover() async {
    if (!mounted || !_disconnected) return;
    _recoverAttempts++;
    final ok = await widget.handle.rejoin();
    if (!mounted) return;
    if (ok) {
      // join 成功：sub 已重新注册，WS 由 rejoin 内部重连；
      // 恢复由 _onSnapshot（收到新鲜快照且自己回到 players）完成。
      return;
    }
    if (_recoverAttempts >= kMaxRecoverAttempts) {
      setState(() => _recoverFailed = true);
      return;
    }
    _recoverTimer?.cancel();
    _recoverTimer = Timer(
      Duration(milliseconds: 500 * (1 << _recoverAttempts)),
      _recover,
    );
  }

  void _ensureEngine() {
    if (_engine != null) return;
    final seq = TetrisRoom.sequence(_snap);
    if (seq.isEmpty) return; // 序列未到位，等下一个 snapshot
    _engine = TetrisEngine(seq);
    _bustDeclared = false;
    _lastSyncAt = null;
    _scheduleGravity();
    _syncNow(); // 进场先报一次空板
  }

  void _teardownEngine() {
    _gravityTimer?.cancel();
    _gravityTimer = null;
    _repeatTimer?.cancel();
    _repeatTimer = null;
    _engine?.dispose();
    _engine = null;
  }

  void _scheduleGravity() {
    _gravityTimer?.cancel();
    final eng = _engine;
    if (eng == null || !eng.alive) return;
    _gravityTimer = Timer.periodic(
      Duration(milliseconds: gravityMs(eng.level)),
      (_) => _gravityTick(),
    );
  }

  void _gravityTick() {
    final eng = _engine;
    if (eng == null || !eng.alive) return;
    final locked = eng.stepDown();
    if (locked) _afterLock();
  }

  /// 任何导致落定的操作后统一处理：同步 + 可能升级重排重力 + game over 检测。
  void _afterLock() {
    _syncNow();
    final eng = _engine;
    if (eng == null) return;
    if (!eng.alive) {
      _declareBust();
    } else {
      _scheduleGravity(); // level 可能提升 → 重力变快
    }
  }

  void _syncNow() {
    final eng = _engine;
    if (eng == null) return;
    final now = DateTime.now();
    if (_lastSyncAt != null &&
        now.difference(_lastSyncAt!) < kSyncMinInterval) {
      return;
    }
    _lastSyncAt = now;
    // 断连瞬间可能失败：吞掉，避免未处理异步异常
    _room.syncState(
      board: eng.boardSnapshot(),
      score: eng.score,
      lines: eng.lines,
      pieceIndex: eng.pieceIndex,
      alive: eng.alive,
    ).catchError((_) {});
  }

  void _declareBust() {
    if (_bustDeclared) return;
    _bustDeclared = true;
    _gravityTimer?.cancel();
    _repeatTimer?.cancel();
    final eng = _engine;
    _room.bust(eng?.score ?? 0).catchError((_) {});
  }

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

  Future<void> _start() async {
    try {
      await _room.start();
    } catch (_) {
      // 断连瞬间失败：由恢复层接管
    }
  }

  Future<void> _reset() async {
    try {
      await _room.reset();
    } catch (_) {
      // 断连瞬间失败：由恢复层接管
    }
  }

  // ── 本地操作（即时，不走网络）──

  void _op(bool Function() action, {bool sync = true}) {
    final eng = _engine;
    if (eng == null || !eng.alive) return;
    final locked = action();
    if (locked && sync) _afterLock();
  }

  void _move(int dx) => _engine?.moveX(dx);
  void _rotateCW() => _engine?.rotateCW();
  void _rotateCCW() => _engine?.rotateCCW();
  void _softDrop() =>
      _op(() => _engine!.stepDown(scorePerCell: kSoftDropScore));
  void _hardDrop() => _op(() => _engine!.hardDrop());

  /// hold 出新块可能 spawn 撞顶 → game over，需检测。
  void _hold() {
    final eng = _engine;
    if (eng == null || !eng.alive) return;
    eng.hold();
    if (!eng.alive) _declareBust();
  }

  // 长按重复（左/右/软降）
  void _beginRepeat(VoidCallback action) {
    action();
    _repeatTimer?.cancel();
    _repeatTimer = Timer.periodic(
      const Duration(milliseconds: 90),
      (_) => action(),
    );
  }

  void _endRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final phase = _snap?.state;
    final Widget content;
    // lobby 与 ready 共用同一张卡片，只切换底部按钮区（三态原地切换）
    if (phase == null || phase == 'lobby' || phase == 'ready') {
      content = _buildLobby();
    } else if (phase == 'ended') {
      content = _buildFinished();
    } else {
      content = _buildPlaying();
    }
    if (!_disconnected) return content;
    // 断线恢复层：终止本地游戏后盖在任意阶段上，恢复后自动消失
    return Stack(
      fit: StackFit.expand,
      children: [
        content,
        ColoredBox(
          color: Theme.of(context).colorScheme.scrim,
          child: Center(
            child: _recoverFailed
                ? _buildRecoverFailed()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text(
                        '连接断开，正在重连…',
                        style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  /// 重连连续失败：给出离开入口，避免无限转圈。
  Widget _buildRecoverFailed() {
    final theme = BoardTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '连接恢复失败',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 16),
        OutlinedButton(
          onPressed: widget.onLeave,
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.btnText,
            side: BorderSide(color: theme.btnText.withValues(alpha: 0.4)),
          ),
          child: const Text('离开房间'),
        ),
      ],
    );
  }

  Widget _buildLobby() {
    final theme = BoardTheme.of(context);
    final code = _snap?.roomCode ?? '------';
    final players = TetrisRoom.players(_snap);
    final readyMap = TetrisRoom.readyMap(_snap);
    final myId = _room.deviceId;
    final phase = _snap?.state;
    final bothReady = phase == 'ready';
    final iAmReady =
        bothReady || _ackedLocally || (readyMap[myId] == true);
    final isHost = _room.isHost;
    final canStart = TetrisRoom.canPerform('START', _snap, isHost: isHost);
    final canAck = TetrisRoom.canPerform('ACK', _snap, isHost: isHost);
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

                    // 玩家列表（圆环头像 + ACK 状态）
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
                            ? (canStart
                                ? FilledButton(
                                    onPressed: _start,
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
                                    onPressed: canAck ? _ack : null,
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

  // ── playing 阶段：cyber v2 外壳（对手预览 + 主棋盘 + 控制按钮） ──

  Widget _buildPlaying() {
    final oppId = TetrisRoom.opponentId(_snap, _room.deviceId);
    final opp = oppId == null ? null : TetrisRoom.stateOf(_snap, oppId);
    final eng = _engine;
    return Scaffold(
      backgroundColor: _cBg,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            children: [
              _buildTopBar(),
              _buildOpponentBar(oppId, opp),
              Expanded(
                child: eng == null
                    ? Center(
                        child: CircularProgressIndicator(color: _cNeon),
                      )
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                _buildSidePanel(eng),
                                SizedBox(width: 8),
                                Expanded(
                                  child: AnimatedBuilder(
                                    animation: eng,
                                    builder: (context, _) =>
                                        _buildCyberBoard(eng),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // 自己已 BUST：叠等待遮罩，看对手实时分数
                          if (!eng.alive) _buildBustWaiting(opp),
                        ],
                      ),
              ),
              _buildControls(),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  /// Cyber 顶栏：左 neon 标题「▣ TETRIS / MATCH」，右比赛时间 + 回合号。
  Widget _buildTopBar() {
    final round = TetrisRoom.sequence(_snap).length; // 用序列长度代替回合号（弱占位）
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '▣ TETRIS / MATCH',
            // proto：标题是 chrome 标签，继承正文 JetBrains Mono 9px/0.2em 常规体；
            // Orbitron 只用于数字强调（.stat .val / .opp .avatar/.delta）
            style: GoogleFonts.jetBrainsMono(
              color: _cNeon,
              fontSize: 9,
              letterSpacing: 1.8,
              shadows: const [Shadow(color: _cTitleGlow, blurRadius: 6)],
            ),
          ),
          Text(
            '09:41 · MATCH ${round.clamp(1, 99)}',
            style: GoogleFonts.jetBrainsMono(
              color: _cInkSub,
              fontSize: 9,
              letterSpacing: 1.8,
            ),
          ),
        ],
      ),
    );
  }

  /// Cyber 底栏：左 ‖ PAUSE，右 1P · SVR-A84K。
  Widget _buildFooter() {
    return Padding(
      padding: EdgeInsets.only(top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '‖ PAUSE',
            style: TextStyle(
              color: _cNeon,
              fontSize: 9,
              letterSpacing: 1.8,
              fontWeight: FontWeight.bold,
              shadows: [Shadow(color: _cLineStrong, blurRadius: 4)],
            ),
          ),
          Text(
            '1P · SVR-A84K',
            style: GoogleFonts.jetBrainsMono(
              color: _cInkSub,
              fontSize: 9,
              letterSpacing: 1.8,
            ),
          ),
        ],
      ),
    );
  }

  /// Cyber 棋盘外壳（neon 边框 + 内嵌暗角 + 扫描线遮罩）+ 原 TetrisBoardView。
  Widget _buildCyberBoard(TetrisEngine eng) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: _cLineStrong, width: 1),
        borderRadius: BorderRadius.circular(4),
        // proto .board-wrap：外辉光 rgba(0,229,255,0.18)（无投影，板体沉入面板）
        boxShadow: [
          BoxShadow(
            color: const Color(0x2E00E5FF),
            blurRadius: 18,
            spreadRadius: 0,
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        fit: StackFit.expand,
        children: [
          TetrisBoardView(
            grid: eng.grid,
            current: eng.current,
            ghostOffset: eng.ghostOffset(),
          ),
          const _BoardInnerShade(),
          const _ScanlineOverlay(),
        ],
      ),
    );
  }

  Widget _buildOpponentBar(
    String? oppId,
    TetrisPlayerState? opp,
  ) {
    final alias = oppId == null
        ? '?'
        : (TetrisRoom.players(_snap)[oppId] ?? '对手');
    final initial = alias.isNotEmpty ? alias[0].toUpperCase() : '?';
    final isDead = opp != null && !opp.alive;
    return Padding(
      padding: EdgeInsets.only(top: 4, bottom: 8),
      child: Container(
        padding: EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: _cLine)),
        ),
        child: Row(
          children: [
            // Cyber avatar：36×36 方块 + 首字母 + neon 边框 + glow
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _cPanel,
                border: Border.all(color: _cLineStrong),
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(color: _cLine, blurRadius: 10),
                  BoxShadow(
                    color: _cLineStrong.withValues(alpha: 0.5),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Text(
                initial,
                style: GoogleFonts.orbitron(
                  color: _cNeon,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(color: _cLineStrong, blurRadius: 6)],
                ),
              ),
            ),
            SizedBox(width: 10),
            // Meta：姓名 + 分数·消行合写
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    alias,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _cInk,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '${opp?.score ?? 0} · L${opp?.lines ?? 0}',
                    style: GoogleFonts.jetBrainsMono(
                      color: _cInkSub,
                      fontSize: 9,
                      letterSpacing: 1.44, // proto 0.16em × 9px
                    ),
                  ),
                ],
              ),
            ),
            // 状态 pill：dead 显示「已 GG」，live 显示最近一次分数 delta（无变化则不渲染）
            if (isDead)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _cPanel,
                  border: Border.all(color: _cDeltaDown),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: _cDeltaDown.withValues(alpha: 0.35),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Text(
                  '已 GG',
                  style: GoogleFonts.orbitron(
                    color: _cDeltaDown,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else if (_oppDelta != null)
              TweenAnimationBuilder<double>(
                key: ValueKey(_oppDelta),
                tween: Tween(begin: 1.25, end: 1),
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: _DeltaBadge(delta: _oppDelta!),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidePanel(TetrisEngine eng) {
    return SizedBox(
      width: 88,
      child: AnimatedBuilder(
        animation: eng,
        builder: (context, _) => Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 点击 HOLD 预览框 = 触发 hold（侧栏交互，不占控制栏位置）
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _hold,
              child: _cyberPanel(
                child: _infoBlock(
                  'HOLD',
                  index: eng.holdIndex == null
                      ? '--'
                      : (eng.holdIndex! + 1).toString().padLeft(2, '0'),
                  child: TetrisPiecePreview(type: eng.holdType),
                ),
              ),
            ),
            _cyberPanel(
              child: _infoBlock(
                'NEXT',
                index: (eng.pieceIndex + 1).toString().padLeft(2, '0'),
                child: TetrisPiecePreview(type: eng.nextType),
              ),
            ),
            // Stats — 自由排列，不包 panel；Orbitron 24px 全 neon + glow
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _stat('SCORE', '${eng.score}'),
                SizedBox(height: 8),
                _stat('LINES', '${eng.lines}'),
                SizedBox(height: 8),
                _stat('LEVEL', eng.level.toString().padLeft(2, '0')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Cyber 侧栏小面板：panel 底 + neon 边框 + CRT 方括号 + 内发光。
  Widget _cyberPanel({required Widget child}) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _cPanel,
            border: Border.all(color: _cLine),
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(color: _cLine, blurRadius: 8),
              BoxShadow(color: const Color(0x66000000), blurRadius: 4, offset: const Offset(0, 2)),
            ],
          ),
          child: child,
        ),
        const Positioned.fill(child: _CyberBrackets(color: _cLineStrong, size: 5, thickness: 1)),
      ],
    );
  }

  /// proto .panel .lbl：'> ' neon 前缀 + label，可带右对齐序列索引（HOLD 02 / NEXT 03）。
  Widget _infoBlock(String label, {String? index, required Widget child}) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: '> ', style: TextStyle(color: _cNeon)),
                    TextSpan(text: label),
                  ],
                ),
                style: TextStyle(
                  color: _cInkSub,
                  fontSize: 9,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (index != null)
                Text(
                  index,
                  style: const TextStyle(
                    color: _cInkSub,
                    fontSize: 9,
                    letterSpacing: 1.8,
                  ),
                ),
            ],
          ),
          SizedBox(height: 6),
          SizedBox(width: 56, height: 56, child: child),
        ],
      );

  /// Cyber 大数字 (Orbitron 24px neon + glow) — 自由排版，无 panel。
  Widget _stat(String label, String value) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: '> ', style: TextStyle(color: _cNeon)),
                TextSpan(text: label),
              ],
            ),
            style: TextStyle(
              color: _cInkSub,
              fontSize: 9,
              letterSpacing: 1.8,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.orbitron(
              color: _cNeon,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1,
              shadows: [Shadow(color: _cLineStrong, blurRadius: 8)],
            ).copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );

  Widget _buildControls() {
    final dead = _engine != null && !_engine!.alive;
    return Padding(
      padding: EdgeInsets.only(top: 8, bottom: 6),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // wrapper：neon 边框 + 对角大括号
          Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x0A00E5FF), Color(0x0000E5FF)],
              ),
              border: Border.all(color: _cLine),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(color: _cLine, blurRadius: 12)],
            ),
            child: Row(
              children: [
                // 左半：MOVE（长按连发）
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ctrlHalfLabel('MOVE', '⟳ hold'),
                      SizedBox(height: 4),
                      Row(
                        children: [
                          _padButton(
                            Icons.arrow_left_rounded,
                            '左',
                            repeat: () => _move(-1),
                            dim: dead,
                          ),
                          _padButton(
                            Icons.arrow_downward_rounded,
                            '软降',
                            repeat: _softDrop,
                            dim: dead,
                          ),
                          _padButton(
                            Icons.arrow_right_rounded,
                            '右',
                            repeat: () => _move(1),
                            dim: dead,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 10),
                // 右半：ACTION（单次）
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ctrlHalfLabel('ACTION', 'tap'),
                      SizedBox(height: 4),
                      Row(
                        children: [
                          _padButton(
                            Icons.rotate_left_rounded,
                            '左旋',
                            onTap: _rotateCCW,
                            dim: dead,
                          ),
                          _padButton(
                            Icons.rotate_right_rounded,
                            '右旋',
                            onTap: _rotateCW,
                            dim: dead,
                          ),
                          _padButton(
                            Icons.vertical_align_bottom_rounded,
                            '硬降',
                            onTap: _hardDrop,
                            accent: true,
                            dim: dead,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // wrapper 对角大括号：proto 只画 TL + BR（.ctrl-wrap::before/::after）
          const Positioned(top: -1, left: -1, child: _CornerBracketTL(color: _cNeon)),
          const Positioned(bottom: -1, right: -1, child: _CornerBracketBR(color: _cNeon)),
        ],
      ),
    );
  }

  /// 控制区左右半的 chip 标签。
  /// proto：8px / 0.20em（8px × 0.20 = 1.6 逻辑像素），hint 继承父级字距。
  Widget _ctrlHalfLabel(String left, String right) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            left,
            style: GoogleFonts.jetBrainsMono(
              color: _cInkFaint,
              fontSize: 8,
              letterSpacing: 1.6,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            right,
            style: GoogleFonts.jetBrainsMono(
              color: _cNeon,
              fontSize: 8,
              letterSpacing: 1.6,
              fontWeight: FontWeight.bold,
              shadows: [Shadow(color: _cLineStrong, blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }

  /// 控制按钮：onTap 单次；repeat 长按连发（左/右/软降）。
  /// dead=true 半透明（自己已 GG，按钮失效）；accent=true 强调色（硬降主操作，neon2 粉）。
  Widget _padButton(
    IconData icon,
    String label, {
    VoidCallback? onTap,
    VoidCallback? repeat,
    bool accent = false,
    bool dim = false,
  }) {
    return _PadButton(
      icon: icon,
      label: label,
      onTap: onTap,
      repeat: repeat,
      onRepeatStart: _beginRepeat,
      onRepeatEnd: _endRepeat,
      accent: accent,
      dim: dim,
    );
  }

  // ── ended ──

  Widget _buildFinished() {
    final theme = BoardTheme.of(context);
    final myId = _room.deviceId;
    final oppId = TetrisRoom.opponentId(_snap, myId);
    final winnerId = TetrisRoom.winner(_snap);
    final iWon = winnerId == myId;
    final msg = iWon ? '我方获胜！' : '对方获胜';
    final oppAlias = _opponentAlias();
    final myFin = TetrisRoom.finishedOf(_snap, myId);
    final oppFin = TetrisRoom.finishedOf(_snap, oppId ?? '');
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.scrim,
      body: SafeArea(
        child: Center(
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 32, vertical: 28),
            decoration: BoxDecoration(
              color: theme.panelBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  iWon ? Icons.emoji_events : Icons.sentiment_dissatisfied,
                  size: 48,
                  color: iWon ? Theme.of(context).colorScheme.tertiary : Theme.of(context).colorScheme.error,
                ),
                SizedBox(height: 12),
                Text(
                  msg,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: iWon ? Theme.of(context).colorScheme.tertiary : Theme.of(context).colorScheme.error,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '按最终分判定（先 GG 扣 ${myFin?.penalty ?? oppFin?.penalty ?? 500}）',
                  style: TextStyle(color: theme.btnSub, fontSize: 11),
                ),
                SizedBox(height: 14),
                // 比分明细
                _scoreRow('我', myFin?.score, myFin, true, theme),
                SizedBox(height: 6),
                _scoreRow(oppAlias, oppFin?.score, oppFin, false, theme),
                SizedBox(height: 16),
                if (_room.isHost)
                  OutlinedButton(
                    onPressed: _reset,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kTetrisAccent,
                      side: BorderSide(color: kTetrisAccent),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: const Text('再来一局'),
                  )
                else
                  Text(
                    '等待房主开始下一局…',
                    style: TextStyle(color: theme.btnSub, fontSize: 13),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 终局比分行：名字 + 最终分（扣分后）/ 原始分（扣分明细）。
  Widget _scoreRow(
    String name,
    int? finalScore,
    TetrisFinalScore? fin,
    bool isMe,
    BoardThemeData theme,
  ) {
    final win = isMe; // 由调用方决定高亮（winner）
    return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              name,
              style: TextStyle(
                color: win ? kTetrisAccent : theme.btnText,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Text(
            '${finalScore ?? 0}',
            style: TextStyle(
              color: win ? kTetrisAccent : theme.btnText,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (fin != null && fin.penalty > 0) ...[
            SizedBox(width: 6),
            Text(
              '(原 ${fin.rawScore} −${fin.penalty})',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error.withValues(alpha: 0.8),
                fontSize: 10,
              ),
            ),
          ] else if (fin != null) ...[
            SizedBox(width: 6),
            Text(
              '(原 ${fin.rawScore})',
              style: TextStyle(color: theme.btnSub, fontSize: 10),
            ),
          ],
        ],
      );
  }

  /// 自己已 BUST、对方仍在玩：叠在主棋盘上的等待遮罩。
  Widget _buildBustWaiting(TetrisPlayerState? opp) {
    return Positioned.fill(
      child: Container(
        color: const Color(0x99000000),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.hourglass_top,
                color: _cNeon,
                size: 40,
                shadows: [Shadow(color: _cLineStrong, blurRadius: 12)],
              ),
              SizedBox(height: 12),
              Text(
                '你已 GG，等待对手完成…',
                style: TextStyle(
                  color: _cInk,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.08,
                ),
              ),
              SizedBox(height: 8),
              Text(
                '对手当前分数 ${opp?.score ?? 0}',
                style: GoogleFonts.jetBrainsMono(
                  color: _cInkSub,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _opponentAlias() {
    final oppId = TetrisRoom.opponentId(_snap, _room.deviceId);
    if (oppId == null) return '对手';
    return TetrisRoom.players(_snap)[oppId] ?? '对手';
  }
}

// ══════════════════════════════════════════════════════════════
// 小组件：圆环头像 + 打勾圆（复用五子棋 UX，未 ready = 首字母，ready = 绿勾）
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
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
                  : Theme.of(context).colorScheme.surface.withValues(alpha: 0.0),
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
                size: 22, color: Theme.of(context).colorScheme.primary)
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

// ══════════════════════════════════════════════════════════════════
// Cyber v2 小部件：CRT 方括号 / 扫描线遮罩 / ⟳ 重复标记 / wrapper 角括号
// ══════════════════════════════════════════════════════════════════

/// proto .opp .delta — 对手分数变化徽章：up 绿 / down 红，Orbitron 14 w700。
class _DeltaBadge extends StatelessWidget {
  const _DeltaBadge({required this.delta});
  final int delta;

  @override
  Widget build(BuildContext context) {
    final up = delta > 0;
    final color = up ? _cDeltaUp : _cDeltaDown;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _cPanel,
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 8),
        ],
      ),
      child: Text(
        up ? '+$delta' : '$delta',
        style: GoogleFonts.orbitron(
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 边框四角的小方括号，赛博 CRT 风。
/// 仅视觉，不接收命中（不阻挡按钮事件）。
class _CyberBrackets extends StatelessWidget {
  const _CyberBrackets({
    this.color = const Color(0xFF00E5FF),
    this.size = 6,
    this.thickness = 1.5,
  });
  final Color color;
  final double size;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    final side = BorderSide(color: color, width: thickness);
    return IgnorePointer(
      child: SizedBox.expand(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: 0, left: 0,
              child: Container(
                width: size, height: size,
                decoration: BoxDecoration(border: Border(top: side, left: side)),
              ),
            ),
            Positioned(
              bottom: 0, right: 0,
              child: Container(
                width: size, height: size,
                decoration: BoxDecoration(border: Border(bottom: side, right: side)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 棋盘 / 容器上的水平扫描线遮罩（CRT 复古）。
class _ScanlineOverlay extends StatelessWidget {
  const _ScanlineOverlay();
  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(painter: _ScanlinePainter()),
      ),
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = _cScanline;
    for (double y = 0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScanlinePainter oldDelegate) => false;
}

/// board-wrap 内嵌暗角（proto inset 0 0 18px rgba(0,0,0,0.4)）— CRT 凹陷感。
/// Flutter BoxShadow 无 inset → 四边 18px 线性渐变手绘。
class _BoardInnerShade extends StatelessWidget {
  const _BoardInnerShade();
  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(painter: _BoardInnerShadePainter()),
      ),
    );
  }
}

class _BoardInnerShadePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const color = Color(0x66000000); // rgba(0,0,0,0.4)
    const fade = 18.0;
    final w = size.width;
    final h = size.height;
    Paint edge(Offset from, Offset to) => Paint()
      ..shader = ui.Gradient.linear(
        from,
        to,
        [color, color.withValues(alpha: 0)],
      );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, fade),
      edge(const Offset(0, 0), const Offset(0, fade)),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, h - fade, w, fade),
      edge(Offset(0, h), Offset(0, h - fade)),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, fade, h),
      edge(const Offset(0, 0), const Offset(fade, 0)),
    );
    canvas.drawRect(
      Rect.fromLTWH(w - fade, 0, fade, h),
      edge(Offset(w, 0), Offset(w - fade, 0)),
    );
  }

  @override
  bool shouldRepaint(covariant _BoardInnerShadePainter oldDelegate) => false;
}

/// 按钮内右上角的 ⟳ 小标记，提示长按连发。
class _RepeatBadge extends StatelessWidget {
  const _RepeatBadge({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 3, right: 5,
      child: IgnorePointer(
        child: Text(
          '⟳',
          style: TextStyle(
            color: color,
            fontSize: 9,
            height: 1,
            shadows: [Shadow(color: color, blurRadius: 4)],
          ),
        ),
      ),
    );
  }
}

/// 控制按钮（proto .btn）— 原型唯一带动效的元素，按压/hover 必须有反馈。
/// hover：边框/文字转 neon + 外辉光；active：下沉 1px + 青色底 tint（.12s ease）。
/// accent（硬降）保持粉系，仅下沉 + 底色加深。
class _PadButton extends StatefulWidget {
  const _PadButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.repeat,
    this.onRepeatStart,
    this.onRepeatEnd,
    this.accent = false,
    this.dim = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final VoidCallback? repeat; // 非空 = 长按连发
  final ValueChanged<VoidCallback>? onRepeatStart;
  final VoidCallback? onRepeatEnd;
  final bool accent;
  final bool dim;

  @override
  State<_PadButton> createState() => _PadButtonState();
}

class _PadButtonState extends State<_PadButton> {
  bool _hovered = false;
  bool _pressed = false;

  void _onTapDown(TapDownDetails _) {
    setState(() => _pressed = true);
    final r = widget.repeat;
    if (r != null) widget.onRepeatStart?.call(r);
  }

  void _onTapUp(TapUpDetails _) => _release();
  void _onTapCancel() => _release();

  void _release() {
    if (!_pressed) return;
    setState(() => _pressed = false);
    if (widget.repeat != null) widget.onRepeatEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final lit = _pressed || _hovered;
    final fg = accent ? _cNeon2 : (lit ? _cNeon : _cInkSub);
    final bgColor = accent
        ? (lit ? const Color(0x2EFF2BD6) : const Color(0x14FF2BD6))
        : (lit ? const Color(0x1A00E5FF) : _cPanel);
    final borderColor = accent ? _cNeon2 : (lit ? _cLineStrong : _cLine);
    final shadows = accent
        ? [
            const BoxShadow(color: Color(0x59FF2BD6), blurRadius: 14),
            const BoxShadow(color: Color(0x33FF2BD6), blurRadius: 4),
          ]
        : [
            const BoxShadow(
              color: Color(0x66000000),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
            if (lit) const BoxShadow(color: Color(0x3300E5FF), blurRadius: 8),
          ];

    return Expanded(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: _onTapDown,
          onTapUp: _onTapUp,
          onTapCancel: _onTapCancel,
          child: Opacity(
            opacity: widget.dim ? 0.35 : 1,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  // active 下沉 1px（proto translateY(1px)）：margin 上+1 下-1
                  margin: EdgeInsets.fromLTRB(
                    2, _pressed ? 5 : 4, 2, _pressed ? 3 : 4,
                  ),
                  height: 56,
                  decoration: BoxDecoration(
                    color: bgColor,
                    border: Border.all(color: borderColor),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: shadows,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        widget.icon,
                        color: fg,
                        size: 22,
                        shadows: accent
                            ? [Shadow(color: const Color(0x8CFF2BD6), blurRadius: 6)]
                            : null,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.label,
                        style: GoogleFonts.jetBrainsMono(
                          color: fg,
                          fontSize: 9,
                          letterSpacing: 0.54, // proto 0.06em × 9px
                        ),
                      ),
                    ],
                  ),
                ),
                // CRT 四角小方括号
                _CyberBrackets(color: accent ? _cNeon2 : _cLine, size: 5, thickness: 1.5),
                // 长按连发 ⟳ 标记
                if (widget.repeat != null) _RepeatBadge(color: _cNeon),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// wrapper 容器外侧的对角大括号（12×12，neon + glow，proto 只用 TL + BR）。
class _CornerBracketTL extends StatelessWidget {
  const _CornerBracketTL({this.color = const Color(0xFF00E5FF)});
  final Color color;
  @override
  Widget build(BuildContext context) {
    final side = BorderSide(color: color, width: 2);
    return IgnorePointer(
      child: Container(
        width: 12, height: 12,
        decoration: BoxDecoration(
          border: Border(top: side, left: side),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6)],
        ),
      ),
    );
  }
}

class _CornerBracketBR extends StatelessWidget {
  const _CornerBracketBR({this.color = const Color(0xFF00E5FF)});
  final Color color;
  @override
  Widget build(BuildContext context) {
    final side = BorderSide(color: color, width: 2);
    return IgnorePointer(
      child: Container(
        width: 12, height: 12,
        decoration: BoxDecoration(
          border: Border(right: side, bottom: side),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6)],
        ),
      ),
    );
  }
}