// lib/lab/demos/tetris_lua/widgets.dart
// 俄罗斯方块 Lua 版 — UI：OnlineGamePage（建房/加入表单在 tetris_forms.dart）
//
// 房间四阶段框架照搬 gomoku/surround（lobby→ready→playing→ended），
// 但 playing 内核完全不同：双方各自本地实时玩（非回合制），
// 服务端只下发共享序列 + 广播双方堆积状态。

import 'dart:async';

import 'package:flutter/material.dart';

import 'engine.dart';
import 'board.dart';
import 'package:xiaodouzi_fr/core/surround_game/board_theme.dart';

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
  bool _lostDeclared = false; // 防止 LOSE 重发
  DateTime? _lastSyncAt; // SYNC 节流

  @override
  void initState() {
    super.initState();
    _room = TetrisRoom(widget.handle);
    _snap = widget.handle.latest;
    _sub = widget.handle.snapshots.listen(_onSnapshot);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _gravityTimer?.cancel();
    _repeatTimer?.cancel();
    _engine?.dispose();
    super.dispose();
  }

  void _onSnapshot(Snapshot s) {
    if (!mounted) return;
    setState(() => _snap = s);

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
      _lostDeclared = false;
    }
    if (_ackedLocally && phase != 'lobby' && phase != 'ready') {
      _ackedLocally = false;
    }
  }

  void _ensureEngine() {
    if (_engine != null) return;
    final seq = TetrisRoom.sequence(_snap);
    if (seq.isEmpty) return; // 序列未到位，等下一个 snapshot
    _engine = TetrisEngine(seq);
    _lostDeclared = false;
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
      _declareLose();
    } else {
      _scheduleGravity(); // level 可能提升 → 重力变快
    }
  }

  void _syncNow() {
    final eng = _engine;
    if (eng == null) return;
    final now = DateTime.now();
    if (_lastSyncAt != null && now.difference(_lastSyncAt!) < kSyncMinInterval) {
      return;
    }
    _lastSyncAt = now;
    _room.syncState(
      board: eng.boardSnapshot(),
      score: eng.score,
      lines: eng.lines,
      pieceIndex: eng.pieceIndex,
      alive: eng.alive,
    );
  }

  void _declareLose() {
    if (_lostDeclared) return;
    _lostDeclared = true;
    _gravityTimer?.cancel();
    _repeatTimer?.cancel();
    _room.lose();
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

  Future<void> _start() async => _room.start();
  Future<void> _reset() async => _room.reset();

  // ── 本地操作（即时，不走网络）──

  void _op(bool Function() action, {bool sync = true}) {
    final eng = _engine;
    if (eng == null || !eng.alive) return;
    final locked = action();
    if (locked && sync) _afterLock();
  }

  void _move(int dx) => _engine?.moveX(dx);
  void _rotate() => _engine?.rotateCW();
  void _softDrop() =>
      _op(() => _engine!.stepDown(scorePerCell: kSoftDropScore));
  void _hardDrop() => _op(() => _engine!.hardDrop());

  /// hold 出新块可能 spawn 撞顶 → game over，需检测。
  void _hold() {
    final eng = _engine;
    if (eng == null || !eng.alive) return;
    eng.hold();
    if (!eng.alive) _declareLose();
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
    if (phase == null || phase == 'lobby') return _buildLobby();
    if (phase == 'ready') return _buildReadyWait();
    if (phase == 'ended') return _buildFinished();
    return _buildPlaying();
  }

  Widget _buildLobby() {
    final theme = BoardTheme.of(context);
    final code = _snap?.roomCode ?? '------';
    final players = TetrisRoom.players(_snap);
    final readyMap = TetrisRoom.readyMap(_snap);
    final myId = _room.deviceId;
    final iAmReady = _ackedLocally || (readyMap[myId] == true);
    return Scaffold(
      backgroundColor: theme.boardSurface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.hourglass_top, size: 64, color: Colors.orange),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    code,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 6,
                      color: Colors.orange,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '等待对手加入…',
                  style: TextStyle(color: theme.btnSub, fontSize: 13),
                ),
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
                        color: Colors.white,
                        size: 20,
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
                  OutlinedButton.icon(
                    onPressed: iAmReady ? null : _ack,
                    icon: Icon(
                      iAmReady
                          ? Icons.check_circle
                          : Icons.check_circle_outlined,
                    ),
                    label: Text(iAmReady ? '已准备 ✓' : '准备好了'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: iAmReady
                          ? Colors.green
                          : Colors.green.shade400,
                      side: BorderSide(
                        color: iAmReady ? Colors.green : Colors.green.shade400,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      minimumSize: const Size(200, 48),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReadyWait() {
    final theme = BoardTheme.of(context);
    final canStart = _room.isHost;
    return Scaffold(
      backgroundColor: theme.boardSurface,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hourglass_top, size: 48, color: Colors.orange),
              const SizedBox(height: 16),
              Text(
                '双方已准备好',
                style: TextStyle(fontSize: 18, color: theme.btnText),
              ),
              const SizedBox(height: 24),
              if (canStart)
                OutlinedButton.icon(
                  onPressed: _start,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('开始游戏'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.green,
                    side: const BorderSide(color: Colors.green),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    minimumSize: const Size(200, 48),
                  ),
                )
              else
                Text('等待房主开始…', style: TextStyle(color: theme.btnSub)),
            ],
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
                    : Row(
                        children: [
                          _buildSidePanel(eng),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: AnimatedBuilder(
                                animation: eng,
                                builder: (context, _) => TetrisBoardView(
                                  grid: eng.grid,
                                  current: eng.current,
                                  ghostOffset: eng.ghostOffset(),
                                ),
                              ),
                            ),
                          ),
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
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _padButton(
                  Icons.arrow_left_rounded,
                  '左',
                  repeat: () => _move(-1),
                ),
                _padButton(
                  Icons.arrow_downward_rounded,
                  '软降',
                  repeat: _softDrop,
                ),
                _padButton(
                  Icons.arrow_right_rounded,
                  '右',
                  repeat: () => _move(1),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 120,
            child: Row(
              children: [
                _padButton(Icons.rotate_right_rounded, '旋转', onTap: _rotate),
                _padButton(
                  Icons.vertical_align_bottom_rounded,
                  '硬降',
                  onTap: _hardDrop,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 控制按钮：onTap 单次；repeat 长按连发（左/右/软降）。
  Widget _padButton(
    IconData icon,
    String label, {
    VoidCallback? onTap,
    VoidCallback? repeat,
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
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(color: Colors.white54, fontSize: 9),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── ended ──

  Widget _buildFinished() {
    final theme = BoardTheme.of(context);
    final winnerId = TetrisRoom.winner(_snap);
    final iWon = winnerId == _room.deviceId;
    final msg = iWon ? '我方获胜！' : '对方获胜';
    final oppAlias = _opponentAlias();
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
                const SizedBox(height: 8),
                Text(
                  '对手：$oppAlias',
                  style: TextStyle(color: theme.btnSub, fontSize: 13),
                ),
                const SizedBox(height: 8),
                if (_engine != null)
                  Text(
                    '本局分数 ${_engine!.score}',
                    style: TextStyle(color: theme.btnSub, fontSize: 13),
                  ),
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

  String _opponentAlias() {
    final oppId = TetrisRoom.opponentId(_snap, _room.deviceId);
    if (oppId == null) return '对手';
    return TetrisRoom.players(_snap)[oppId] ?? '对手';
  }
}
