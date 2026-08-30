// lib/core/chess/p2p/chess_lobby_page.dart
//
// 社交房间号入口页（social-room-code-pattern）—— 单表单加入/建房 + 等待房。
//
// 与其它 Lua 游戏（gomoku / jungle / surround…）的 LobbyEntryPage 同构：
//   双方输入同一房间号 + 昵称 → 点击"进入对局" →
//   transport.tryJoinOrCreate：房间存在 → join；404 → 用此号建房
//   （先到者 = 房主 = 白方先手，后到者执黑）。不再区分"创建/加入"两个按钮。
//
// 阶段：
//   entry  单表单（昵称 + 房间号 + 规则提示 + 错误提示）
//   room   等待房（房间号 chip + 玩家列表 + 自动开局提示）
//   服务端 state == "playing"（或 "ended" 断线重连）→ onStarted(handle)
//   交给业务层接管（push ChessRoomPage）。
//
// v2（READY 门）：服务端不再"双人到齐自动 playing"。进入房间后先停在
//   state = "lobby"（准备阶段）—— 本页等待房显示"双方已就绪"提示并快速
//   push ChessRoomPage，由房间页渲染准备卡片（"准备好了" → "开始游戏"）。
//   导航时机放宽到 state ∈ (lobby, ready, playing, ended)，因为房间页
//   自带 lobby/ready/playing/ended 四态 UI（v2 之前只等 playing 才 push）。
//
// 409 区分（服务端 message 关键词，per social-room-code-pattern）：
//   "code collision" → 撞号（房间号被占，提示换一个）
//   "join rejected"  → 满员（guest 槽已占，kChessScript 的 rejected_join）
//
// 颜色走 context.chessColors（v6.2.1 主题通道）；昵称走 LuaGameAlias
// （与其它 Lua 房间游戏共享，一处输入处处同步）。

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/lua/lua_game_alias.dart';
import '../../../widgets/context_chess_colors.dart';
import '../../net_engine/relay_v3/relay_v3_transport.dart';
import 'chess_identity.dart';
import 'chess_script.dart';

/// 社交房间号入口页 —— 单表单 + 等待房 + onStarted。
class ChessLobbyPage extends StatefulWidget {
  const ChessLobbyPage({
    super.key,
    required this.relayUrl,
    required this.onStarted,
    this.title = '国际象棋在线',
    this.actionsBuilder,
    this.transportBuilder,
  });

  /// Relay 服务地址（如 http://47.110.80.47:8988）。
  final String relayUrl;

  /// 服务端 state 进入 lobby / ready / playing / ended 时触发（断线重连同码再进
  /// 也走这里），把 [RoomHandle] 交给业务层接管（push ChessRoomPage）。
  ///
  /// v2（READY 门）：lobby 也触发 —— 房间页自带准备卡片（"准备好了" / "开始游戏"），
  /// 不必等 playing 才 push（旧版只等 playing/ended）。
  final void Function(RoomHandle handle) onStarted;

  /// AppBar 标题。
  final String title;

  /// 业务层附加 AppBar actions（如"换肤"按钮），前置到断开按钮之前。
  final List<Widget> Function(BuildContext context)? actionsBuilder;

  /// 测试注入：自定义 transport 构造（默认 null → 真实 RelayV3Transport）。
  final RelayV3Transport Function(String alias, String deviceId)?
      transportBuilder;

  @override
  State<ChessLobbyPage> createState() => ChessLobbyPageState();
}

class ChessLobbyPageState extends State<ChessLobbyPage> {
  _ChessLobbyPhase _phase = _ChessLobbyPhase.entry;

  final _aliasCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  RelayV3Transport? _transport;
  RoomHandle? _handle;
  StreamSubscription<Snapshot>? _snapSub;
  Snapshot? _snapshot;

  /// onStarted 是否已触发（防快照风暴重复 push）。
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // 共享昵称（与其它 Lua 游戏通用）：load 回填 + 监听实时同步。
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
    _snapSub?.cancel();
    super.dispose();
  }

  // ——— 单表单进入：join 优先，404 → 建房 ———

  /// 房间号合法性：4–6 位大写字母数字，不含易混字符（0/O/1/I/L）。
  static const String _kConfusingChars = '0O1IL';

  String? _validateCode(String code) {
    if (code.length < 4 || code.length > 6) return '房间号为 4–6 位大写字母数字';
    if (code.contains(RegExp('[$_kConfusingChars]'))) {
      return '房间号不能包含 0/O/1/I/L（易混淆）';
    }
    return null;
  }

  /// 单表单智能匹配：先按输入的房间号尝试 join；不存在则用此号创建。
  /// 撞号（409 code collision）→ 房间号被占，提示换号；
  /// 满员（409 join rejected）→ guest 槽已占，kChessScript 拒绝。
  Future<void> _go() async {
    final alias = _aliasCtrl.text.trim();
    if (alias.isEmpty) {
      setState(() => _error = '请输入昵称');
      return;
    }
    final code = _codeCtrl.text.trim().toUpperCase();
    final codeError = _validateCode(code);
    if (codeError != null) {
      setState(() => _error = codeError);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // 稳定身份：登录 uid 优先，未登录回退设备级 UUID（chess_identity.dart）。
      // 断线重连/重新进房身份不丢（Bug 1/2 根因修复 —— 会话级 deviceId 已弃用）。
      final deviceId = await ChessIdentity.resolve();
      final t = widget.transportBuilder?.call(alias, deviceId) ??
          RelayV3Transport(
            relayUrl: widget.relayUrl,
            alias: alias,
            deviceId: deviceId,
          );
      await LuaGameAlias.save(alias);
      final h = await t.tryJoinOrCreate(
        code: code,
        script: kChessScript,
        initialParams: {'device_id': t.deviceId, 'alias': alias},
        maxPlayers: 2,
      );
      if (!mounted) return;
      _transport = t;
      _handle = h;
      _subscribeSnapshot(h);
      setState(() {
        _snapshot = h.latest;
        _phase = _ChessLobbyPhase.room;
        _busy = false;
      });
    } on RelayV3Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _mapEntryError(e, code);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  /// 服务端两种 409 用 message 关键词区分（撞号 vs 满员）。
  String _mapEntryError(RelayV3Exception e, String code) {
    final body = e.body.toLowerCase();
    if (e.statusCode == 409 && body.contains('code collision')) {
      return '房间号 $code 已被占用，请换一个';
    }
    if (e.statusCode == 409 && body.contains('join rejected')) {
      return '房间 $code 已满员，无法加入';
    }
    if (e.statusCode == 404) {
      return '房间号 $code 不存在且创建失败';
    }
    return '进入失败（${e.statusCode}）';
  }

  // ——— 快照订阅 + 开始 ———

  void _subscribeSnapshot(RoomHandle h) {
    _snapSub?.cancel();
    _snapSub = h.snapshots.listen((snap) {
      if (!mounted) return;
      setState(() => _snapshot = snap);
      // v2（READY 门）：state ∈ {lobby, ready, playing, ended} 都 push 房间页。
      // 房间页自带四态 UI：lobby 渲染准备卡片（ACK），ready 渲染"开始游戏"，
      // playing 渲染棋盘，ended 渲染终局卡片（host 可 RESET 再来一局）。
      // 不 push 的条件 = 只有 null 或已 push 过（防快照风暴重复 push）。
      if (!_started && (snap.state == 'lobby' ||
          snap.state == 'ready' ||
          snap.state == 'playing' ||
          snap.state == 'ended')) {
        _started = true;
        widget.onStarted(h);
      }
    });
  }

  /// 重置回入口表单（对弈页 pop 后由外层调用 / 用户点断开）。
  Future<void> resetToEntry() async {
    _started = false;
    _snapSub?.cancel();
    _snapSub = null;
    final h = _handle;
    _handle = null;
    _transport = null;
    if (!mounted) return;
    setState(() {
      _snapshot = null;
      _phase = _ChessLobbyPhase.entry;
      _busy = false;
      _error = null;
    });
    await h?.dispose();
  }

  // ——— UI ———

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        actions: [
          ...?widget.actionsBuilder?.call(context),
          if (_phase == _ChessLobbyPhase.room)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: resetToEntry,
              tooltip: '断开',
            ),
        ],
      ),
      body: SafeArea(
        child: switch (_phase) {
          _ChessLobbyPhase.entry => _buildEntry(context),
          _ChessLobbyPhase.room => _buildRoom(context),
        },
      ),
    );
  }

  /// 入口单表单：昵称 + 房间号 + 提示 + 错误 + "进入对局"。
  Widget _buildEntry(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.chessColors;
    final inputDec = InputDecoration(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.meeting_room_outlined,
                size: 56,
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 12),
              Text(
                '输入房间号，与朋友对弈',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _aliasCtrl,
                decoration: inputDec.copyWith(
                  labelText: '昵称',
                  hintText: '如：小白',
                  prefixIcon: const Icon(Icons.person_outline),
                ),
                onChanged: LuaGameAlias.save,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _codeCtrl,
                decoration: inputDec.copyWith(
                  labelText: '房间号',
                  hintText: '4–6 位大写字母数字',
                  prefixIcon: const Icon(Icons.tag),
                ),
                style: theme.textTheme.bodyLarge?.copyWith(
                  letterSpacing: 4,
                  fontWeight: FontWeight.w600,
                ),
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                onSubmitted: (_) => _busy ? null : _go(),
              ),
              const SizedBox(height: 4),
              // 规则提示（浅色块）：让用户预期"先到 = 房主 = 白方"
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: colors.lightSquare.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        '◐',
                        style: TextStyle(
                          color: colors.coordinateLabel,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '与朋友约定同一房间号即可对战：谁先到谁是房主（执白先行），后到者执黑。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.coordinateLabel,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _go,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        '进入对局',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 等待房：房间号 chip + 玩家列表（角色标注）+ 开始/等待。
  Widget _buildRoom(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.chessColors;
    final snap = _snapshot;
    final code = snap?.roomCode ?? '------';
    final players = _extractPlayers();
    final hostId = snap?.context['host_id']?.toString();
    final guestId = snap?.context['guest_id']?.toString();
    final myId = _transport?.deviceId;
    final guestIn = guestId != null && guestId.isNotEmpty && players.containsKey(guestId);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                guestIn ? '双方已就绪' : '等待对手',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              // 房间号 chip（大号 + 字距，方便口头/截图分享）
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: colors.lightSquare.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: colors.gridLine.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    code,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 8,
                      color: colors.coordinateLabel,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (!guestIn)
                Text(
                  '把房间号发给朋友，输入同一号即可加入',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.coordinateLabel),
                ),
              const SizedBox(height: 20),
              // 玩家列表（host = 白方先手在前）
              for (final entry in players.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        entry.key == hostId
                            ? Icons.circle_outlined
                            : Icons.circle,
                        size: 14,
                        color: entry.key == hostId
                            ? colors.coordinateLabel
                            : colors.gridLine,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${entry.value}'
                          '${entry.key == myId ? "  (我)" : ""}'
                          '${entry.key == hostId ? " · 执白" : " · 执黑"}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: entry.key == myId
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              // v2（READY 门）：双人到齐后停在 lobby 准备阶段，玩家在房间页
              // 点"准备好了"（ACK）→ ready → host 点"开始游戏"（DEAL）→ playing。
              // 这里只做轻量提示 —— 真正的准备卡片由 ChessRoomPage 渲染
              // （onStarted 在 lobby 就已 push，本页等待房仅瞬态停留）。
              if (guestIn)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '双方已就绪，进入准备…',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ],
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '等待朋友加入…',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: colors.coordinateLabel),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 从 snapshot context 提取 players（device_id → alias）。
  Map<String, String> _extractPlayers() {
    final snap = _snapshot;
    if (snap == null) return const {};
    final raw = snap.context['players'];
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
  }
}

enum _ChessLobbyPhase { entry, room }
