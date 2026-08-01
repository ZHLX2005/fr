// lib/lab/demos/coup_lua/widgets.dart
// 政变（Coup）Lua 版 — UI 组件：LobbyEntryPage / OnlineGamePage / 角色卡 widget
//
// 布局沿用 reversi_lua 范式：
//   - lobby / ready 同一张卡片；START 按钮
//   - playing 阶段：顶部回合条 + 中央卡牌面板 + 下方 7 个动作按钮（我的回合）/ 质疑&阻断面板（响应期）
//   - ended 阶段：终局 overlay + 房主"再来一局"按钮
//
// 角色卡 widget：双色边框（边框主义）+ 卡名 + 图标 + 角色描述 + 下方 3 个按钮（按 cur_phase 切换）

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:xiaodouzi_fr/core/surround_game/board_theme.dart'
    show BoardTheme, BoardThemeData;

import 'constants.dart';
import 'engine.dart'
    show
        CoupRoom,
        CoupPlayerState,
        CoupCurrentAction,
        CoupRole,
        CoupAction,
        CoupPhase,
        actionLabel,
        roleLabel,
        roleFromWire;

import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart'
    show RelayV3Exception, RoomHandle, Snapshot, RelayV3Transport;
import 'package:xiaodouzi_fr/services/lua/lua_game_alias.dart';

import 'engine.dart' show kCoupScript;

// ══════════════════════════════════════════════════════════════
// Lobby Entry Page
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
        relayUrl: kCoupRelayUrl,
        alias: alias,
        deviceId: 'cp-${DateTime.now().microsecondsSinceEpoch}',
      );
      await LuaGameAlias.save(alias);
      final h = await t.tryJoinOrCreate(
        code: code,
        script: kCoupScript,
        initialParams: {'device_id': t.deviceId, 'alias': alias},
        maxPlayers: 6,
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
    final inputDec = (String hint) => InputDecoration(
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
        decoration: inputDec('昵称'),
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
            child: Text('♛',
                style: TextStyle(color: theme.btnSub, fontSize: 13)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '2–6 人对局，输入同一房间号即加入；房主建房 + 开局',
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
              child: Text(_error!,
                  style: const TextStyle(
                      color: Color(0xFFB33A1F), fontSize: 12, height: 1.4)),
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
          child: _busy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: theme.panelBg,
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
  late final CoupRoom _room;

  @override
  void initState() {
    super.initState();
    _room = CoupRoom(widget.handle);
    _snap = widget.handle.latest;
    _sub = widget.handle.snapshots.listen((s) {
      if (!mounted) return;
      setState(() => _snap = s);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = BoardTheme.of(context);
    final snap = _snap;
    if (snap == null) {
      return Scaffold(
        backgroundColor: theme.boardSurface,
        appBar: AppBar(
            backgroundColor: theme.boardSurface,
            foregroundColor: theme.btnText,
            title: const Text('加载中…')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final phase = _room.phase(snap);
    final state = snap.state;
    if (state == 'ended') return _buildFinished(theme);
    if (state == 'lobby' || state == 'ready') return _buildLobby(theme);
    // playing
    if (phase == CoupPhase.loseCard) return _buildLoseCard(theme);
    if (phase == CoupPhase.exchange) return _buildExchange(theme);
    return _buildPlaying(theme);
  }

  // ── lobby / ready ──

  Widget _buildLobby(BoardThemeData theme) {
    final snap = _snap!;
    final code = snap.roomCode;
    final ps = _room.players(snap);
    final order = _room.playerOrder(snap);
    final isHost = _room.isHost;
    final state = snap.state;
    final n = ps.length;

    return Scaffold(
      backgroundColor: theme.boardSurface,
      appBar: AppBar(
        backgroundColor: theme.boardSurface,
        foregroundColor: theme.btnText,
        elevation: 0,
        title: Text(state == 'ready' ? '准备开始' : '等待玩家'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            onPressed: widget.onLeave,
          ),
        ],
      ),
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
                child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Text(state == 'ready' ? '已就绪' : '政变 · 等待对手',
                      style: TextStyle(
                        color: theme.btnText,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      )),
                  const SizedBox(height: 6),
                  Container(width: 24, height: 2, color: theme.btnText),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: theme.btnText.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                          color: theme.btnText.withValues(alpha: 0.2),
                          width: 1),
                    ),
                    child: Text(code,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 8,
                          color: theme.btnText,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        )),
                  ),
                  const SizedBox(height: 18),
                  Text('玩家 $n / 6',
                      style: TextStyle(
                          color: theme.btnSub, fontSize: 13, letterSpacing: 1)),
                  const SizedBox(height: 14),
                  ...order.map((did) {
                    final p = ps[did];
                    if (p == null) return const SizedBox.shrink();
                    final isMe = did == _room.deviceId;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor:
                              theme.btnText.withValues(alpha: 0.12),
                          child: Text(
                            p.alias.isNotEmpty
                                ? p.alias[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                                color: theme.btnText,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${p.alias}${isMe ? "  (我)" : ""}',
                            style: TextStyle(
                                color: theme.btnText,
                                fontSize: 15,
                                fontWeight: isMe
                                    ? FontWeight.w600
                                    : FontWeight.w500),
                          ),
                        ),
                      ]),
                    );
                  }),
                  if (n < 2) ...[
                    const SizedBox(height: 16),
                    Text('至少需要 2 位玩家',
                        style: TextStyle(
                            color: theme.btnSub, fontSize: 12, height: 1.4)),
                  ],
                  const SizedBox(height: 22),
                  if (isHost && n >= 2) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: state == 'ready'
                            ? () => _room.start()
                            : () => _room.ack(),
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.btnText,
                          foregroundColor: theme.panelBg,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                        child: Text(state == 'ready' ? '开始游戏 ▸' : '准备好了',
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 2)),
                      ),
                    ),
                  ] else if (!isHost && state == 'lobby') ...[
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () => _room.ack(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF16A34A),
                          side: const BorderSide(
                              color: Color(0xFF16A34A), width: 1.6),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('准备好了',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 2)),
                      ),
                    ),
                  ] else if (state == 'ready') ...[
                    Text('等待房主开始…',
                        style: TextStyle(
                            color: theme.btnSub,
                            fontSize: 13,
                            letterSpacing: 1)),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── playing：动作 + 角色卡 + 响应面板 ──

  Widget _buildPlaying(BoardThemeData theme) {
    final snap = _snap!;
    final ps = _room.players(snap);
    final order = _room.playerOrder(snap);
    final curId = _room.currentPlayerId(snap);
    final me = ps[_room.deviceId];
    final myTurn = _room.isMyTurn(snap);
    final phase = _room.phase(snap);
    final curAct = _room.currentAction(snap);

    return Scaffold(
      backgroundColor: theme.boardSurface,
      appBar: AppBar(
        backgroundColor: theme.boardSurface,
        foregroundColor: theme.btnText,
        elevation: 0,
        title: Text('房间 ${snap.roomCode}'),
      ),
      body: SafeArea(
        child: Column(children: [
          // 顶部回合条
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: theme.panelBg.withValues(alpha: 0.5),
            child: Row(children: [
              Icon(
                myTurn ? Icons.play_arrow_rounded : Icons.hourglass_empty,
                size: 18,
                color: theme.btnText,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _statusText(snap, ps, myTurn, phase, curAct),
                  style: TextStyle(
                      color: theme.btnText,
                      fontSize: 14,
                      fontWeight: FontWeight.w500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),

          // 中间玩家 + 卡牌面板（Expanded）
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 对手卡片网格
                  ...order.where((did) => did != _room.deviceId).map((did) {
                    final p = ps[did];
                    if (p == null) return const SizedBox.shrink();
                    final isCur = did == curId;
                    return _OpponentRow(
                      player: p,
                      isCur: isCur,
                      theme: theme,
                    );
                  }),
                  const SizedBox(height: 16),
                  // 我自己（详细卡牌）
                  if (me != null)
                    _MyCardRow(player: me, theme: theme, room: _room, snap: snap),
                ],
              ),
            ),
          ),

          // 底部动作 / 响应面板
          // 顶部固定工具栏：角色能力 + 退出
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.panelBg.withValues(alpha: 0.7),
              border: Border(
                  bottom: BorderSide(
                      color: theme.panelBorder, width: 0.6)),
            ),
            child: Row(children: [
              TextButton.icon(
                onPressed: () => showRoleAbilitySheet(context),
                icon: const Icon(Icons.menu_book_outlined, size: 16),
                label: const Text('角色能力',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
                style: TextButton.styleFrom(
                  foregroundColor: theme.btnSub,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(0, 32),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.logout_outlined, size: 18),
                onPressed: widget.onLeave,
                tooltip: '退出',
                visualDensity: VisualDensity.compact,
              ),
            ]),
          ),

          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              color: theme.panelBg,
              border: Border(
                  top: BorderSide(color: theme.panelBorder, width: 1)),
            ),
            child: _buildActionPanel(theme, snap, myTurn, phase, curAct, me, ps),
          ),
        ]),
      ),
    );
  }

  String _statusText(
    Snapshot snap,
    Map<String, CoupPlayerState> ps,
    bool myTurn,
    CoupPhase phase,
    CoupCurrentAction? curAct,
  ) {
    final curId = _room.currentPlayerId(snap);
    final curAlias = curId == null ? '?' : (ps[curId]?.alias ?? '?');
    final challengerId = _room.challenger(snap);
    final challengerAlias = challengerId == null
        ? '?'
        : (ps[challengerId]?.alias ?? challengerId.substring(0, 6));

    if (phase == CoupPhase.challenge && curAct != null) {
      final claim = curAct.claimerCard == null
          ? ''
          : '（声称 ${roleLabel(curAct.claimerCard!)}）';
      if (curAct.source == _room.deviceId && challengerId != null) {
        return '$challengerAlias 质疑我有 ${curAct.claimerCard == null ? "?" : roleLabel(curAct.claimerCard!)} 卡 — 翻牌或认输';
      }
      return '${curAct.source == _room.deviceId ? "我" : curAlias} 主张 ${actionLabel(curAct.type)}$claim — 等待质疑';
    }
    if (phase == CoupPhase.reveal && curAct != null) {
      final claim = curAct.claimerCard == null ? '' : '${roleLabel(curAct.claimerCard!)} ';
      final bl = _room.blocker(snap);
      final isBlockReveal = bl != null;
      final src = isBlockReveal ? bl : curAct.source;
      final srcAlias = src == _room.deviceId
          ? '我'
          : (ps[src]?.alias ?? '?');
      if (src == _room.deviceId) {
        return '$challengerAlias 质疑我有 $claim卡 — 我必须翻牌或认输';
      }
      return '$challengerAlias 质疑 $srcAlias 的 $claim卡 — 等待翻牌';
    }
    if (phase == CoupPhase.block && curAct != null) {
      if (curAct.type == CoupAction.foreignAid) {
        final amSource = curAct.source == _room.deviceId;
        return amSource ? '外援 — 等待对手阻断或通过' : '对方外援 — 我可用公爵阻断';
      }
      final blockerName = curAct.target == _room.deviceId ? "我" : curAlias;
      return '$blockerName 可阻断 ${actionLabel(curAct.type)}';
    }
    if (phase == CoupPhase.blockChallenge && curAct != null) {
      final bl = _room.blocker(snap);
      final blAlias = bl == null ? '?' : (ps[bl]?.alias ?? '?');
      if (curAct.source == _room.deviceId) {
        return '$blAlias 阻断 ${actionLabel(curAct.type)} — 我可反质疑';
      }
      if (bl == _room.deviceId) {
        return '${curAct.source == _room.deviceId ? "?" : (ps[curAct.source]?.alias ?? "?")} 反质疑我的阻断 — 翻牌或认输';
      }
      return '$blAlias 阻断 ${actionLabel(curAct.type)}（${roleLabel(curAct.claimerCard ?? CoupRole.contessa)}）— 等待反质疑';
    }
    return myTurn ? '轮到我行动' : '等待 $curAlias 行动…';
  }

  Widget _buildActionPanel(
    BoardThemeData theme,
    Snapshot snap,
    bool myTurn,
    CoupPhase phase,
    CoupCurrentAction? curAct,
    CoupPlayerState? me,
    Map<String, CoupPlayerState> ps,
  ) {
    // 1. 被质疑方（主动作发起人 / 阻断人 在 challenge / reveal / blockChallenge 阶段）：
    //    必须翻牌证明 或 直接认输（自动 LOSE_CARD）
    if (_room.isBeingChallenged(snap) && me != null) {
      final claim = curAct?.claimerCard;
      return _buildRevealPanel(theme, me, claim);
    }

    // 2. 我可以质疑：显示挑战行（指向主动作发起人或反质疑期的阻断人）
    final chTarget = _room.myChallengeTarget(snap);
    if (chTarget != null) {
      return _buildResponseRow(
        theme,
        '是否质疑对方声称有 ${roleLabel(chTarget.claimRole)}？',
        onChallenge: () => _room.challenge(chTarget.target, chTarget.claimRole),
        onPass: () => _room.passResponse(),
      );
    }

    // 3. 我是质疑方（已发起质疑，等待被质疑方翻牌或认输）
    if (_room.challenger(snap) == _room.deviceId && phase == CoupPhase.reveal) {
      final ca = curAct;
      final isBlockPhase = snap.context['cur_phase']?.toString() == 'reveal' &&
          _room.blocker(snap) != null;
      String targetAlias = '?';
      if (ca != null) {
        final ps = snap.context['players'];
        if (ps is Map) {
          final src = isBlockPhase ? _room.blocker(snap) : ca.source;
          if (src != null) {
            targetAlias = ((ps[src] as Map?) ?? const {})['alias']?.toString() ?? '?';
          }
        }
      }
      final claimRole = ca?.claimerCard == null ? '' : '${roleLabel(ca!.claimerCard!)} ';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          '已质疑 $targetAlias 的 $claimRole卡 — 等待翻牌或认输',
          style: TextStyle(color: theme.btnText, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      );
    }

    // 3. 阻断期：FOREIGN_AID 任意非发起人可阻断；STEAL/ASSASSINATE 仅被影响方可阻断
    if (phase == CoupPhase.block && curAct != null) {
      final amSource = curAct.source == _room.deviceId;
      final canRespond = curAct.type == CoupAction.foreignAid
          ? !amSource                         // FA：只要不是发起人就能阻断/通过
          : curAct.target == _room.deviceId;  // STEAL/ASSASSINATE：仅目标
      if (canRespond) return _buildBlockRow(theme, curAct.type);
    }

    // 4. 我的回合：动作按钮组
    if (myTurn && phase == CoupPhase.action && me != null) {
      return _buildActionButtons(theme, me);
    }

    // 5. 其他情况：等待（区分场景，让玩家知道在等什么）
    if (phase == CoupPhase.challenge && curAct != null) {
      // 挑战期：我是 source → 等别人质疑；不是 source → 看我能不能质疑
      // （分支 2 已处理我能质疑的情况；这里只剩 source 在等）
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          curAct.source == _room.deviceId
              ? '等待其他玩家质疑或通过'
              : '等待 ${ps[curAct.source]?.alias ?? "?"} 行动…',
          style: TextStyle(color: theme.btnSub, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        '等待其他玩家…',
        style: TextStyle(color: theme.btnSub, fontSize: 13),
        textAlign: TextAlign.center,
      ),
    );
  }

  /// 被质疑方面板：翻牌（持有声称卡 → REVEAL）或认输（不持有 → LOSE_CARD）
  Widget _buildRevealPanel(
    BoardThemeData theme,
    CoupPlayerState me,
    CoupRole? claim,
  ) {
    // 判断我是否持有声称的卡
    bool? card1IsClaim;
    bool? card2IsClaim;
    if (claim != null) {
      card1IsClaim = me.card1Alive && me.card1 == claim.name;
      card2IsClaim = me.card2Alive && me.card2 == claim.name;
    }
    final canReveal = claim != null && (card1IsClaim == true || card2IsClaim == true);

    return Column(children: [
      Text(
        claim == null
            ? '被质疑：点击下方"翻牌"尝试证明；无该卡则认输'
            : canReveal
                ? '你被要求证明持有 ${roleLabel(claim)} 卡 — 你有，按"翻出"'
                : '你被要求证明持有 ${roleLabel(claim)} 卡 — 你没有，认输',
        style: TextStyle(
            color: claim != null && !canReveal
                ? const Color(0xFFB33A1F)
                : theme.btnText,
            fontSize: 13,
            fontWeight: FontWeight.w600),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: SizedBox(
            height: 44,
            child: FilledButton.icon(
              onPressed: canReveal ? () => _room.reveal(claim) : null,
              icon: const Icon(Icons.style_outlined, size: 18),
              label: Text(
                claim == null ? '翻牌' : '翻出 ${roleLabel(claim)}',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
                disabledBackgroundColor: theme.btnSub.withValues(alpha: 0.2),
                disabledForegroundColor: theme.panelBg.withValues(alpha: 0.6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              onPressed: () => _pickLoseCardAndConcede(),
              icon: const Icon(Icons.flag_outlined, size: 18),
              label: Text(
                ((me.card1Alive ? 1 : 0) + (me.card2Alive ? 1 : 0)) > 1
                    ? '认输（失 1 张）'
                    : '认输',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB33A1F),
                side: const BorderSide(
                    color: Color(0xFFB33A1F), width: 1.6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ),
      ]),
    ]);
  }

  Future<void> _pickLoseCardAndConcede() async {
    final me = _room.myPlayer(_snap!);
    if (me == null) return;
    final slots = <int>[];
    if (me.card1Alive) slots.add(1);
    if (me.card2Alive) slots.add(2);
    if (slots.isEmpty) return;
    int slot = slots.first;
    if (slots.length > 1) {
      final picked = await showDialog<int>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('认输：选择失去哪张卡'),
          children: slots
              .map((s) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, s),
                    child: Text('卡 $s（${_cardLabelForSlot(me, s)}）'),
                  ))
              .toList(),
        ),
      );
      if (picked == null) return;
      slot = picked;
    }
    await _room.loseCard(slot);
  }

  String _cardLabelForSlot(CoupPlayerState me, int slot) {
    final r = slot == 1
        ? (me.card1 == null ? null : roleFromWire(me.card1!))
        : (me.card2 == null ? null : roleFromWire(me.card2!));
    return r == null ? '?' : roleLabel(r);
  }

  Widget _buildActionButtons(BoardThemeData theme, CoupPlayerState me) {
    final coins = me.coins;
    final canCoup = coins >= 7;
    final canAssassinate = coins >= 3;
    final canAct = (CoupAction a) {
      if (a == CoupAction.coup) return canCoup;
      if (a == CoupAction.assassinate) return canAssassinate;
      // 金币 ≥10 必须 COUP（标准规则）
      if (coins >= 10 && a != CoupAction.coup) return false;
      return true;
    };

    final actions = CoupAction.values;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: actions.map((a) {
        final enabled = canAct(a);
        return SizedBox(
          width: 96,
          height: 44,
          child: FilledButton(
            onPressed: enabled ? () => _onAct(a) : null,
            style: FilledButton.styleFrom(
              backgroundColor:
                  enabled ? theme.btnText : theme.btnSub.withValues(alpha: 0.2),
              foregroundColor: theme.panelBg,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            child: Text(
              actionLabel(a),
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildResponseRow(
    BoardThemeData theme,
    String hint, {
    required VoidCallback onChallenge,
    required VoidCallback onPass,
  }) {
    return Column(children: [
      Text(hint,
          style: TextStyle(
              color: theme.btnText,
              fontSize: 13,
              fontWeight: FontWeight.w500)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: SizedBox(
            height: 44,
            child: FilledButton.icon(
              onPressed: onChallenge,
              icon: const Icon(Icons.warning_amber_rounded, size: 18),
              label: const Text('质疑',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB33A1F),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 44,
            child: OutlinedButton(
              onPressed: onPass,
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.btnText,
                side: BorderSide(color: theme.panelBorder, width: 1.4),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('不质疑 / 通过',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ]),
    ]);
  }

  Widget _buildBlockRow(BoardThemeData theme, CoupAction type) {
    // 根据动作类型显示可选阻断角色
    final candidates = <CoupRole>[];
    if (type == CoupAction.foreignAid) candidates.add(CoupRole.duke);
    if (type == CoupAction.steal) {
      candidates.addAll([CoupRole.captain, CoupRole.ambassador]);
    }
    if (type == CoupAction.assassinate) candidates.add(CoupRole.contessa);
    return Column(children: [
      Text('声明持有阻断卡（可被对方反质疑）',
          style: TextStyle(
              color: theme.btnText,
              fontSize: 13,
              fontWeight: FontWeight.w500)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ...candidates.map(
            (r) => SizedBox(
              width: 110,
              height: 40,
              child: OutlinedButton(
                onPressed: () => _room.block(r),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.btnText,
                  side: BorderSide(color: theme.panelBorder, width: 1.4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: Text('阻断 · ${roleLabel(r)}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
          SizedBox(
            width: 110,
            height: 40,
            child: FilledButton(
              onPressed: () => _room.passResponse(),
              style: FilledButton.styleFrom(
                backgroundColor: theme.btnText,
                foregroundColor: theme.panelBg,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: const Text('不阻断',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    ]);
  }

  Future<void> _onAct(CoupAction a) async {
    // 需要目标的 STEAL / ASSASSINATE / COUP
    String? target;
    if (a == CoupAction.steal ||
        a == CoupAction.assassinate ||
        a == CoupAction.coup) {
      target = await _pickTarget();
      if (target == null) return;
    }
    await _room.act(a, target: target);
  }

  Future<String?> _pickTarget() async {
    final ps = _room.players(_snap!);
    final candidates =
        ps.entries.where((e) => e.key != _room.deviceId && e.value.alive).toList();
    if (candidates.isEmpty) return null;
    if (candidates.length == 1) return candidates.first.key;
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择目标'),
        children: candidates
            .map((c) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, c.key),
                  child: Text(c.value.alias),
                ))
            .toList(),
      ),
    );
  }

  // ── loseCard / exchange ──

  Widget _buildLoseCard(BoardThemeData theme) {
    final snap = _snap!;
    final me = _room.myPlayer(snap);
    final isMe = _room.loser(snap) == _room.deviceId;
    return Scaffold(
      backgroundColor: theme.boardSurface,
      appBar: AppBar(
        backgroundColor: theme.boardSurface,
        foregroundColor: theme.btnText,
        elevation: 0,
        title: const Text('失去一张卡'),
      ),
      body: SafeArea(
        child: Center(
          child: isMe && me != null
              ? _loseCardPicker(theme, me)
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '等待 ${_room.loser(snap) == null ? "?" : _room.players(snap)[_room.loser(snap)!]?.alias ?? "?"} 失去一张卡…',
                    style: TextStyle(
                        color: theme.btnText,
                        fontSize: 15,
                        fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _loseCardPicker(BoardThemeData theme, CoupPlayerState me) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.panelBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.panelBorder),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('失去哪张卡？',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (me.card1Alive)
            _cardSlot(
              theme,
              role: me.card1 == null ? null : roleFromWire(me.card1!),
              slot: 1,
            ),
          if (me.card1Alive) const SizedBox(width: 12),
          if (me.card2Alive)
            _cardSlot(
              theme,
              role: me.card2 == null ? null : roleFromWire(me.card2!),
              slot: 2,
            ),
        ]),
      ]),
    );
  }

  Widget _cardSlot(BoardThemeData theme,
      {required CoupRole? role, required int slot}) {
    return InkWell(
      onTap: () => _room.loseCard(slot),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 100,
        height: 140,
        decoration: BoxDecoration(
          color: roleColor(role ?? CoupRole.contessa).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: roleColor(role ?? CoupRole.contessa), width: 2.4),
        ),
        alignment: Alignment.center,
        child: Text(
          role == null ? '?' : roleLabel(role),
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: roleColor(role ?? CoupRole.contessa)),
        ),
      ),
    );
  }

  Widget _buildExchange(BoardThemeData theme) {
    final snap = _snap!;
    final cards = _room.exchangeCards(snap);
    final isMe = _room.exchangePlayer(snap) == _room.deviceId;
    final keepN = (snap.context['exchange_keep'] as num?)?.toInt() ?? 2;
    return Scaffold(
      backgroundColor: theme.boardSurface,
      appBar: AppBar(
        backgroundColor: theme.boardSurface,
        foregroundColor: theme.btnText,
        elevation: 0,
        title: Text('换牌 · 保留 $keepN 张'),
      ),
      body: SafeArea(
        child: Center(
          child: isMe
              ? _exchangePicker(theme, cards)
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '等待 ${_room.exchangePlayer(snap) == null ? "?" : _room.players(snap)[_room.exchangePlayer(snap)!]?.alias ?? "?"} 选牌…',
                    style: TextStyle(
                        color: theme.btnText,
                        fontSize: 15,
                        fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _exchangePicker(BoardThemeData theme, List<String> cards) {
    // 服务端下发的需保留张数（1 或 2）；缺省按 2
    final keepN = (_snap!.context['exchange_keep'] as num?)?.toInt() ?? 2;
    final selected = <int>{};
    return StatefulBuilder(builder: (ctx, setSB) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.panelBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.panelBorder),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('点选 $keepN 张保留（其余放回牌库）',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: List.generate(cards.length, (i) {
              final r = roleFromWire(cards[i]) ?? CoupRole.contessa;
              final sel = selected.contains(i);
              return InkWell(
                onTap: () => setSB(() {
                  if (sel) {
                    selected.remove(i);
                  } else if (selected.length < keepN) {
                    selected.add(i);
                  }
                }),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 88,
                  height: 120,
                  decoration: BoxDecoration(
                    color: roleColor(r).withValues(alpha: sel ? 0.32 : 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: roleColor(r),
                        width: sel ? 3.0 : 2.0),
                  ),
                  alignment: Alignment.center,
                  child: Text(roleLabel(r),
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: roleColor(r))),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton(
              onPressed: selected.length == keepN
                  ? () {
                      final list = selected.toList()..sort();
                      _room.exchangeKeep(list); // 传数组
                    }
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: theme.btnText,
                foregroundColor: theme.panelBg,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: Text(selected.length == keepN
                  ? '确认保留 $keepN 张'
                  : '请选择 $keepN 张',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      );
    });
  }

  // ── ended ──

  Widget _buildFinished(BoardThemeData theme) {
    final snap = _snap!;
    final winnerId = _room.winner(snap);
    final ps = _room.players(snap);
    final winnerAlias = winnerId == null ? '?' : (ps[winnerId]?.alias ?? '?');
    final iWon = winnerId == _room.deviceId;
    final isHost = _room.isHost;
    return Scaffold(
      backgroundColor: theme.boardSurface,
      body: SafeArea(
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(24),
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
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                  iWon ? Icons.emoji_events : Icons.flag_outlined,
                  size: 48,
                  color: iWon
                      ? const Color(0xFFFFB300)
                      : theme.btnSub),
              const SizedBox(height: 12),
              Text(iWon ? '我方获胜！' : '$winnerAlias 获胜',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: theme.btnText,
                      letterSpacing: 2)),
              const SizedBox(height: 20),
              if (isHost) ...[
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: () => _room.reset(),
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
                ),
              ] else ...[
                Text('等待房主开始下一局…',
                    style: TextStyle(
                        color: theme.btnSub,
                        fontSize: 13,
                        letterSpacing: 1)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 对手横条（缩略）
// ══════════════════════════════════════════════════════════════

class _OpponentRow extends StatelessWidget {
  const _OpponentRow({
    required this.player,
    required this.isCur,
    required this.theme,
  });
  final CoupPlayerState player;
  final bool isCur;
  final BoardThemeData theme;

  @override
  Widget build(BuildContext context) {
    final cardColor = player.card1Alive
        ? roleColor(player.card1 == null ? null : roleFromWire(player.card1!))
        : theme.btnSub;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isCur
            ? theme.btnText.withValues(alpha: 0.06)
            : theme.panelBg.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isCur ? theme.btnText : theme.panelBorder,
            width: isCur ? 1.6 : 1),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: cardColor.withValues(alpha: 0.2),
          child: Text(
            player.alias.isNotEmpty ? player.alias[0].toUpperCase() : '?',
            style: TextStyle(
                color: theme.btnText, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${player.alias}${isCur ? "  · 行动中" : ""}',
                style: TextStyle(
                    color: theme.btnText,
                    fontSize: 14,
                    fontWeight: isCur ? FontWeight.w700 : FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.monetization_on,
                    size: 12, color: theme.btnSub),
                const SizedBox(width: 2),
                Text('${player.coins}',
                    style: TextStyle(color: theme.btnSub, fontSize: 12)),
                const SizedBox(width: 10),
                Icon(Icons.style, size: 12, color: theme.btnSub),
                const SizedBox(width: 2),
                Text('${player.handCount}',
                    style: TextStyle(color: theme.btnSub, fontSize: 12)),
              ]),
            ],
          ),
        ),
        // 背面卡 × N
        ...List.generate(player.handCount.clamp(0, 2), (i) {
          return Container(
            width: 22,
            height: 30,
            margin: const EdgeInsets.only(left: 4),
            decoration: BoxDecoration(
              color: theme.btnText.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: theme.btnText, width: 1),
            ),
          );
        }),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 我自己（详细卡牌）
// ══════════════════════════════════════════════════════════════

class _MyCardRow extends StatelessWidget {
  const _MyCardRow({
    required this.player,
    required this.theme,
    required this.room,
    required this.snap,
  });
  final CoupPlayerState player;
  final BoardThemeData theme;
  final CoupRoom room;
  final Snapshot snap;

  @override
  Widget build(BuildContext context) {
    final isBeingChallenged = room.isBeingChallenged(snap);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.panelBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isBeingChallenged
                ? const Color(0xFFB33A1F)
                : theme.btnText.withValues(alpha: 0.3),
            width: 2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('${player.alias}（我）',
              style: TextStyle(
                  color: theme.btnText,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.help_outline, size: 18, color: theme.btnSub),
            tooltip: '查看角色能力',
            onPressed: () => showRoleAbilitySheet(context),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          const SizedBox(width: 4),
          Icon(Icons.monetization_on,
              size: 14, color: theme.btnSub),
          const SizedBox(width: 4),
          Text('${player.coins}',
              style: TextStyle(
                  color: theme.btnText,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          if (player.card1Alive)
            _MyCardSlot(
              role: player.card1 == null ? null : roleFromWire(player.card1!),
              theme: theme,
            ),
          if (player.card1Alive) const SizedBox(width: 10),
          if (player.card2Alive)
            _MyCardSlot(
              role: player.card2 == null ? null : roleFromWire(player.card2!),
              theme: theme,
            ),
        ]),
      ],
      ),
    );
  }
}

class _MyCardSlot extends StatelessWidget {
  const _MyCardSlot({required this.role, required this.theme});
  final CoupRole? role;
  final BoardThemeData theme;

  @override
  Widget build(BuildContext context) {
    final r = role ?? CoupRole.contessa;
    final color = roleColor(r);
    return Container(
      width: 110,
      height: 150,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color, width: 3.0),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(roleLabel(r),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: color)),
          const SizedBox(height: 6),
          Text(_roleDesc(r),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 10,
                  height: 1.3,
                  color: theme.btnText.withValues(alpha: 0.7))),
        ],
      ),
    );
  }
}

String _roleDesc(CoupRole r) {
  switch (r) {
    case CoupRole.duke:
      return '征税 (+3)\n阻断外援';
    case CoupRole.assassin:
      return '刺杀 (-3)\n目标失 1 卡';
    case CoupRole.captain:
      return '偷窃\n阻断偷窃';
    case CoupRole.ambassador:
      return '换牌\n阻断偷窃';
    case CoupRole.contessa:
      return '阻断刺杀';
  }
}

Color roleColor(CoupRole? r) {
  switch (r) {
    case CoupRole.duke:
      return const Color(0xFF6750A4); // 紫
    case CoupRole.assassin:
      return const Color(0xFFB33A1F); // 红
    case CoupRole.captain:
      return const Color(0xFF1F6FEB); // 蓝
    case CoupRole.ambassador:
      return const Color(0xFF16A34A); // 绿
    case CoupRole.contessa:
      return const Color(0xFFB58900); // 金
    default:
      return const Color(0xFF666666);
  }
}

// ══════════════════════════════════════════════════════════════
// 角色能力介绍 Sheet（点击 "?" 图标打开）
// ══════════════════════════════════════════════════════════════

Future<void> showRoleAbilitySheet(BuildContext context) {
  final theme = BoardTheme.of(context);
  return showModalBottomSheet(
    context: context,
    backgroundColor: theme.panelBg,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.btnSub.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Text('角色与能力',
                    style: TextStyle(
                        color: theme.btnText,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2)),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close, color: theme.btnSub),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ]),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.btnText.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '每位玩家持 2 张角色卡 + 2 金币。\n'
                  '声称有某角色卡即可执行其动作（或阻断）。\n'
                  '任何玩家可质疑；翻牌失败者失 1 卡。',
                  style: TextStyle(
                      color: theme.btnSub, fontSize: 12, height: 1.5),
                ),
              ),
              const SizedBox(height: 16),
              ...CoupRole.values.map((r) => _AbilityCard(role: r)),
              const SizedBox(height: 20),
              Text('基础动作（不需声称）',
                  style: TextStyle(
                      color: theme.btnText,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1)),
              const SizedBox(height: 8),
              _BaseActionRow(
                icon: Icons.payments_outlined,
                title: '收入 INCOME',
                desc: '+1 金币；任何时候可用',
                color: theme.btnSub,
              ),
              _BaseActionRow(
                icon: Icons.handshake_outlined,
                title: '外援 FOREIGN_AID',
                desc: '+2 金币；任何玩家可声明持有公爵（Duke）阻断',
                color: theme.btnSub,
              ),
              _BaseActionRow(
                icon: Icons.gavel_outlined,
                title: '政变 COUP (-7)',
                desc: '强制目标失去 1 张卡；不可被阻断；金币 ≥10 必须政变',
                color: const Color(0xFFB33A1F),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _AbilityCard extends StatelessWidget {
  const _AbilityCard({required this.role});
  final CoupRole role;

  @override
  Widget build(BuildContext context) {
    final theme = BoardTheme.of(context);
    final color = roleColor(role);
    final wire = role.name;
    final name = roleLabel(role);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.panelBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 2.2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color, width: 2),
            ),
            alignment: Alignment.center,
            child: Text(
              wire.substring(0, 1).toUpperCase(),
              style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    style: TextStyle(
                        color: color,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1)),
                Text(wire.toUpperCase(),
                    style: TextStyle(
                        color: theme.btnSub,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.5)),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 10),
        ..._roleAbilityLines(role, theme, color),
      ]),
    );
  }
}

List<Widget> _roleAbilityLines(
    CoupRole role, BoardThemeData theme, Color color) {
  final rows = <(String, String, Color)>[];
  switch (role) {
    case CoupRole.duke:
      rows.add(('主动作', '征税 TAX：+3 金币（声称持有公爵）', color));
      rows.add(('阻断', '可声明阻断 FOREIGN_AID（外援）', color));
    case CoupRole.assassin:
      rows.add(('主动作', '刺杀 ASSASSINATE：-3 金币，目标失 1 卡', color));
      rows.add(('被阻断', '可被 Contessa 阻断', const Color(0xFFB58900)));
    case CoupRole.captain:
      rows.add(('主动作', '偷窃 STEAL：从目标偷 1~2 金币（声称队长）', color));
      rows.add(('阻断', '可声明阻断 STEAL', color));
    case CoupRole.ambassador:
      rows.add(('主动作', '换牌 EXCHANGE：从牌库抽 2 张，保留 2 张', color));
      rows.add(('阻断', '可声明阻断 STEAL', color));
    case CoupRole.contessa:
      rows.add(('主动作', '（无）', theme.btnSub));
      rows.add(('阻断', '可声明阻断 ASSASSINATE', color));
  }
  return rows
      .map((r) => Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                margin: const EdgeInsets.only(top: 5),
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(color: r.$3, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                        color: theme.btnText, fontSize: 13, height: 1.4),
                    children: [
                      TextSpan(
                        text: '${r.$1}：',
                        style: TextStyle(
                            color: r.$3, fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: r.$2),
                    ],
                  ),
                ),
              ),
            ]),
          ))
      .toList();
}

class _BaseActionRow extends StatelessWidget {
  const _BaseActionRow({
    required this.icon,
    required this.title,
    required this.desc,
    required this.color,
  });
  final IconData icon;
  final String title;
  final String desc;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = BoardTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                  color: theme.btnText, fontSize: 13, height: 1.4),
              children: [
                TextSpan(
                  text: '$title：',
                  style:
                      TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
                TextSpan(text: desc),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}