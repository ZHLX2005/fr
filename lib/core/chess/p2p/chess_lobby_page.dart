// lib/core/chess/p2p/chess_lobby_page.dart
//
// 社交房间号入口页（social-room-code-pattern）—— 单表单加入/建房 + 过渡 loading。
//
// 与其它 Lua 游戏（gomoku / jungle / surround…）的 LobbyEntryPage 同构：
//   双方输入同一房间号 + 昵称 → 点击"进入对局" →
//   transport.tryJoinOrCreate：房间存在 → join；404 → 用此号建房
//   （先到者 = 房主 = 白方先手，后到者执黑）。不再区分"创建/加入"两个按钮。
//
// 阶段：
//   entry  单表单（昵称 + 房间号 + 规则提示 + 错误提示）
//   room   过渡 loading（仅转圈 —— 房间号 / 玩家 / 准备卡片全由房间页渲染）
//   服务端 state == "lobby"/"ready"/"playing"/"ended" → onStarted(handle)
//   交给业务层接管（push ChessRoomPage）。
//
// v2（READY 门）：服务端不再"双人到齐自动 playing"。进入房间后先停在
//   state = "lobby"（准备阶段）—— 本页只显示 loading，随即 push
//   ChessRoomPage，由房间页渲染准备卡片（"准备好了" → "开始游戏"）。
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
import '../endgame/chess_endgame.dart';
import 'chess_identity.dart';
import 'script/chess_script.dart';

/// 建房者执子选择（v4）：见 [ChessLobbyPageState._resolveHostColorParam] /
/// [_hostChoice] 默认值逻辑。
enum _HostColorChoice { white, black, random, auto }

/// 社交房间号入口页 —— 单表单 + 过渡 loading + onStarted。
class ChessLobbyPage extends StatefulWidget {
  const ChessLobbyPage({
    super.key,
    required this.relayUrl,
    required this.onStarted,
    this.title = '国际象棋在线',
    this.actionsBuilder,
    this.transportBuilder,
    this.initialEndgame,
    this.onClearEndgame,
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

  /// 残局开局快照（非 null → 建房 initial_params 带 initial_fen，房间从
  /// 该局面开始；host 执先手方）。null = 标准开局。
  ///
  /// 仅"你建房"时生效（tryJoinOrCreate join 已存在房间时服务端忽略
  /// initial_params）—— 表单提示块说明这点。
  final ChessEndgameSnapshot? initialEndgame;

  /// 清除残局选择（chip X 按钮；调用方 setState 置空 initialEndgame）。
  final VoidCallback? onClearEndgame;

  @override
  State<ChessLobbyPage> createState() => ChessLobbyPageState();
}

class ChessLobbyPageState extends State<ChessLobbyPage> {
  _ChessLobbyPhase _phase = _ChessLobbyPhase.entry;

  final _aliasCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  RoomHandle? _handle;
  StreamSubscription<Snapshot>? _snapSub;

  /// onStarted 是否已触发（防快照风暴重复 push）。
  bool _started = false;

  // v4：建房时 host 选执子身份。残局模式下多一个 `auto`（按 FEN 推断后解析）
  // — 标准开局默认 `white`，残局默认 `auto`。
  _HostColorChoice _hostChoice = _HostColorChoice.white;

  @override
  void initState() {
    super.initState();
    _hostChoice = widget.initialEndgame != null
        ? _HostColorChoice.auto
        : _HostColorChoice.white;
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

  /// 把 UI 选项解析成服务端协议值：
  ///   `white` / `black` / `random` → 直接透传
  ///   `auto`                       → client 端用 FEN 推（仅残局模式可达），
  ///                                   解析成具体 'w' 或 'b'；不带 FEN 返回 null
  ///                                   （服务端看不到 'auto' 这种 wire 取值）
  String? _resolveHostColorParam() {
    switch (_hostChoice) {
      case _HostColorChoice.white:
        return 'w';
      case _HostColorChoice.black:
        return 'b';
      case _HostColorChoice.random:
        return 'random';
      case _HostColorChoice.auto:
        final e = widget.initialEndgame;
        if (e == null) return null;
        return ChessEndgame.sideFromFen(e.fen);
    }
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
      // 残局开局（v4）：
      //   · initial_fen 建房时服务端消费；join 已存在房间时被忽略
      //   · host_color 决定 host 执子色（'w' / 'b' / 'random'）；
      //     残局模式下与 FEN 不一致时服务端会"强翻转"残局 FEN，让 host 永远是先手方
      //   · 'auto' 仅残局模式出现：客户端先解析成具体 'w' / 'b' 再发送
      //     （服务端不识别 'auto' 这种 wire 取值）
      // 已移除 v3 的 initial_side（服务端忽略，host_color 替代）。
      final endgame = widget.initialEndgame;
      final initialParams = <String, dynamic>{
        'device_id': t.deviceId,
        'alias': alias,
      };
      if (endgame != null) {
        initialParams['initial_fen'] = endgame.fen;
      }
      final hc = _resolveHostColorParam();
      if (hc != null) {
        initialParams['host_color'] = hc;
      }
      final h = await t.tryJoinOrCreate(
        code: code,
        script: kChessScript,
        initialParams: initialParams,
        maxPlayers: 2,
      );
      if (!mounted) return;
      _handle = h;
      _subscribeSnapshot(h);
      setState(() {
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
    if (!mounted) return;
    setState(() {
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
          // 过渡 loading：只保留转圈 —— 房间号 / 玩家列表 / 准备卡片全部由
          // 房间页渲染，避免等待房与房间页两套 UI 的视觉跳变。
          _ChessLobbyPhase.room => const Center(
              child: CircularProgressIndicator(),
            ),
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
              // 残局选择 chip（非 null 时显示；X 清除回标准开局）。
              if (widget.initialEndgame != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color:
                          theme.colorScheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.extension_outlined,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '残局：${widget.initialEndgame!.label ?? '快照'}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      GestureDetector(
                        onTap: widget.onClearEndgame,
                        child: Icon(
                          Icons.close,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // 执子选择按钮（v4）：紧凑 OutlinedButton 行（无动画，
// 单行 3-4 按钮，避免 Wrap 多行挤占 viewport；测试与小屏都友好）。
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _hostButton(
                      label: '执白（先手）',
                      value: _HostColorChoice.white,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _hostButton(
                      label: '执黑（后手）',
                      value: _HostColorChoice.black,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _hostButton(
                      label: '随机',
                      value: _HostColorChoice.random,
                    ),
                  ),
                  if (widget.initialEndgame != null) ...[
                    const SizedBox(width: 6),
                    Expanded(
                      child: _hostButton(
                        label: '由残局决定',
                        value: _HostColorChoice.auto,
                      ),
                    ),
                  ],
                ],
              ),
              // 规则提示（浅色块）：让用户预期"先到 = 房主 = 执先手方"
              const SizedBox(height: 16),
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
                        _ruleText(),
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

  /// 执子选择按钮（v4）：单选 OutlinedButton.Filled 风格（selected 视觉对齐 M3）。
  /// 单行 Row + Expanded 分配，避免 Wrap 多行挤占 viewport。
  Widget _hostButton({
    required String label,
    required _HostColorChoice value,
  }) {
    final selected = _hostChoice == value;
    return OutlinedButton(
      onPressed: () => setState(() => _hostChoice = value),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        minimumSize: const Size(0, 36),
        backgroundColor:
            selected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12) : null,
        side: BorderSide(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outlineVariant,
          width: selected ? 1.6 : 1.0,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }

  /// 规则提示文案（v4）：根据是否带残局与执子选择动态输出。
  String _ruleText() {
    final e = widget.initialEndgame;
    if (e == null) {
      // 标准开局（v5 不再镜像 FEN；host 选黑时由棋规决定 guest 执白先走）：
      switch (_hostChoice) {
        case _HostColorChoice.white:
          return '与朋友约定同一房间号对战：你执白（先手），后到者执黑（后手）。'
              '谁先到谁是房主，对方加入时自动分配对方颜色。';
        case _HostColorChoice.black:
          return '与朋友约定同一房间号对战：你执黑（后手，对方先走），后到者执白（先手）。'
              '服务端不翻转局面；棋规白先由对方（执白者）走出第一步。';
        case _HostColorChoice.random:
          return '与朋友约定同一房间号对战：建房瞬间随机分配你的执子颜色，'
              '后到者执对方颜色。';
        case _HostColorChoice.auto:
          // 标准开局不会到 auto，分支兜底
          return '与朋友约定同一房间号对战。';
      }
    }
    // 残局模式（v5 不再强翻转残局 FEN；先手方由 FEN 第 2 字段决定，host 选执子色）
    switch (_hostChoice) {
      case _HostColorChoice.auto:
        return '残局开局：房间从所选局面开始，先手方按残局 FEN 第 2 字段决定。'
            '残局仅在"你创建房间"时生效 —— 若对方已用此号建房，你加入的是对方的房间。';
      case _HostColorChoice.white:
      case _HostColorChoice.black:
        final mine = _hostChoice == _HostColorChoice.white ? '白' : '黑';
        return '残局开局：你选执$mine；服务端不翻转残局 FEN（残局原貌保留）。'
            '先手方仍由残局 FEN 决定 —— 若你执$mine 且 FEN 是黑先，'
            '对方（执对侧色）走第一步。';
      case _HostColorChoice.random:
        return '残局开局：建房瞬间随机决定你的执子颜色；'
            '服务端不翻转残局 FEN（残局原貌保留）。';
    }
  }
}

enum _ChessLobbyPhase { entry, room }
