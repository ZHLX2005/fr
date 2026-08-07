// lib/lab/demos/tetris_lua/widgets.dart
// 俄罗斯方块 Lua 版 — UI：LobbyEntryPage（单表单智能匹配）+ OnlineGamePage
//
// UI 规范对齐五子棋（versus-game-room-template v2026-07-26）：
//   - LobbyEntryPage 单表单：昵称 + 房间号 + 「进入对局」→ tryJoinOrCreate
//   - lobby / ready 共用同一张卡片，底部按钮三态原地切换
//   - 标题跟随 phase：等待对手 → 双方已就绪
//
// playing 内核（本地实时非回合制）完全保留不动。

import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/net_engine/relay_v3/relay_device_id.dart';

import 'engine.dart';
import 'board.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart'
    show RelayV3Exception, WSCloseEvent;
import 'package:xiaodouzi_fr/core/surround_game/board_theme.dart';
import 'package:xiaodouzi_fr/services/lua/lua_game_alias.dart';

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
        relayUrl: kTetrisRelayUrl,
        alias: alias,
        deviceId: await RelayDeviceId.get(),
      );
      await LuaGameAlias.save(alias);
      final h = await t.tryJoinOrCreate(
        code: code,
        script: kTetrisScript,
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
      TextField(
        controller: _aliasCtrl,
        decoration: inputDec('昵称（如：玩家 A）'),
        style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w500, color: theme.btnText),
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
            child:
                Text('◐', style: TextStyle(color: theme.btnSub, fontSize: 13)),
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
                style: const TextStyle(
                    color: _warnColor, fontSize: 12, height: 1.4),
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

/// 暖红色（错误提示，避免纯红）
const Color _warnColor = Color(0xFFB33A1F);

/// 断线重连连续失败的判定次数（join 失败按 0.5s·2^n 退避重试）
const int kMaxRecoverAttempts = 5;

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
    }
    if (_ackedLocally && phase != 'lobby' && phase != 'ready') {
      _ackedLocally = false;
    }
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
          color: Colors.black54,
          child: Center(
            child: _recoverFailed
                ? _buildRecoverFailed()
                : const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text(
                        '连接断开，正在重连…',
                        style: TextStyle(color: Colors.white),
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
        const Text(
          '连接恢复失败',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
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

                    // 玩家列表（圆环头像 + ACK 状态）
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

  // ── playing 阶段：对手预览 + 主棋盘 + 控制按钮 ──

  Widget _buildPlaying() {
    final theme = BoardTheme.of(context);
    final oppId = TetrisRoom.opponentId(_snap, _room.deviceId);
    final opp = oppId == null ? null : TetrisRoom.stateOf(_snap, oppId);
    final eng = _engine;
    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            children: [
              _buildOpponentBar(theme, oppId, opp),
              Expanded(
                child: eng == null
                    ? const Center(child: CircularProgressIndicator())
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                _buildSidePanel(eng),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: AnimatedBuilder(
                                    animation: eng,
                                    builder: (context, _) => TetrisBoardView(
                                      grid: eng.grid,
                                      current: eng.current,
                                      ghostOffset: eng.ghostOffset(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // 自己已 BUST：叠等待遮罩，看对手实时分数
                          if (!eng.alive) _buildBustWaiting(theme, oppId, opp),
                        ],
                      ),
              ),
              _buildControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOpponentBar(
    BoardThemeData theme,
    String? oppId,
    TetrisPlayerState? opp,
  ) {
    final alias = oppId == null
        ? '?'
        : (TetrisRoom.players(_snap)[oppId] ?? '对手');
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: SizedBox(
        height: 84,
        child: Row(
          children: [
            SizedBox(
              width: 42,
              height: 84,
              child: opp == null
                  ? Container(
                      color: const Color(0xFF1E293B),
                      child: const Center(
                        child: Icon(
                          Icons.person_outline,
                          color: Colors.white38,
                        ),
                      ),
                    )
                  : TetrisMiniBoard(board: opp.board),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    alias,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '分数 ${opp?.score ?? 0}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '消行 ${opp?.lines ?? 0}',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (opp != null && !opp.alive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '已 GG',
                  style: TextStyle(color: Colors.redAccent, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidePanel(TetrisEngine eng) {
    return SizedBox(
      width: 72,
      child: AnimatedBuilder(
        animation: eng,
        builder: (context, _) => Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 点击 HOLD 预览框 = 触发 hold（侧栏交互，不占控制栏位置）
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _hold,
              child: _infoBlock('HOLD', TetrisPiecePreview(type: eng.holdType)),
            ),
            _infoBlock('NEXT', TetrisPiecePreview(type: eng.nextType)),
            Column(
              children: [
                _stat('分数', '${eng.score}', kTetrisAccent),
                const SizedBox(height: 6),
                _stat('消行', '${eng.lines}', Colors.greenAccent),
                const SizedBox(height: 6),
                _stat('等级', '${eng.level}', Colors.amberAccent),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoBlock(String label, Widget child) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 10,
          letterSpacing: 1,
        ),
      ),
      const SizedBox(height: 4),
      SizedBox(width: 56, height: 56, child: child),
    ],
  );

  Widget _stat(String label, String value, Color color) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9)),
      Text(
        value,
        style: TextStyle(
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    ],
  );

  Widget _buildControls() {
    final eng = _engine;
    final dead = eng != null && !eng.alive;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Row(
        children: [
          // 左半：方向键（左移 / 软降 / 右移，长按连发）
          Expanded(
            child: Row(
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
          ),
          const SizedBox(width: 4),
          // 右半：动作键（左旋 / 右旋 / 硬降，单次）
          Expanded(
            child: Row(
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
          ),
        ],
      ),
    );
  }

  /// 控制按钮：onTap 单次；repeat 长按连发（左/右/软降）。
  /// dead=true 半透明（自己已 GG，按钮失效）；accent=true 强调色（硬降主操作）。
  Widget _padButton(
    IconData icon,
    String label, {
    VoidCallback? onTap,
    VoidCallback? repeat,
    bool accent = false,
    bool dim = false,
  }) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onTapDown: repeat == null ? null : (_) => _beginRepeat(repeat),
        onTapUp: repeat == null ? null : (_) => _endRepeat(),
        onTapCancel: repeat == null ? null : _endRepeat,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
          height: 58,
          decoration: BoxDecoration(
            color: accent
                ? kTetrisAccent.withValues(alpha: 0.18)
                : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: accent
                  ? kTetrisAccent.withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Opacity(
            opacity: dim ? 0.35 : 1,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: accent ? kTetrisAccent : Colors.white,
                  size: 24,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    color: accent ? kTetrisAccent : Colors.white54,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
      backgroundColor: const Color(0xFF0B1120),
      body: SafeArea(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
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
                  color: iWon ? Colors.amberAccent : Colors.redAccent,
                ),
                const SizedBox(height: 12),
                Text(
                  msg,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: iWon ? Colors.amberAccent : Colors.redAccent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '按最终分判定（先 GG 扣 ${myFin?.penalty ?? oppFin?.penalty ?? 500}）',
                  style: TextStyle(color: theme.btnSub, fontSize: 11),
                ),
                const SizedBox(height: 14),
                // 比分明细
                _scoreRow('我', myFin?.score, myFin, true, theme),
                const SizedBox(height: 6),
                _scoreRow(oppAlias, oppFin?.score, oppFin, false, theme),
                const SizedBox(height: 16),
                if (_room.isHost)
                  OutlinedButton(
                    onPressed: _reset,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kTetrisAccent,
                      side: const BorderSide(color: kTetrisAccent),
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
          const SizedBox(width: 6),
          Text(
            '(原 ${fin.rawScore} −${fin.penalty})',
            style: TextStyle(
              color: Colors.redAccent.withValues(alpha: 0.8),
              fontSize: 10,
            ),
          ),
        ] else if (fin != null) ...[
          const SizedBox(width: 6),
          Text(
            '(原 ${fin.rawScore})',
            style: TextStyle(color: theme.btnSub, fontSize: 10),
          ),
        ],
      ],
    );
  }

  /// 自己已 BUST、对方仍在玩：叠在主棋盘上的等待遮罩。
  Widget _buildBustWaiting(
    BoardThemeData theme,
    String? oppId,
    TetrisPlayerState? opp,
  ) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.hourglass_top,
                color: Colors.amberAccent,
                size: 40,
              ),
              const SizedBox(height: 12),
              const Text(
                '你已 GG，等待对手完成…',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '对手当前分数 ${opp?.score ?? 0}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
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
