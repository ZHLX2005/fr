// lib/core/chess/p2p/chess_lobby_page.dart
//
// 社交房间号入口页（social-room-code-pattern）—— v6：双入口分流。
//
// ## v6 流程改动（与 v5 对比）
//
// v5：单表单 + chip 行（执白/执黑/随机/由残局决定）+ 单一"进入对局"按钮
// v6：单表单 + 双入口按钮 ——
//   · "创建房间"（FilledButton，full width）→ push ChessRoomConfigPage →
//     用户显式选 host/guest 角色与残局 first_moker → 拿到 ChessRoomConfig →
//     tryJoinOrCreate(initialParams={host_color, first_mover, initial_fen?})
//   · "加入房间"（OutlinedButton，full width）→ 直接 tryJoinOrCreate
//     （不带 host_color / first_mover / initial_fen；服务端 join 路径忽略）
//
// 与其它 Lua 游戏（gomoku / jungle / surround…）的 LobbyEntryPage 同构。
//
// 阶段：
//   entry  单表单（昵称 + 房间号 + 残局 chip + 错误提示）
//   room   过渡 loading（仅转圈 —— 房间号 / 玩家 / 准备卡片全由房间页渲染）
//   服务端 state == "lobby"/"ready"/"playing"/"ended" → onStarted(handle)
//   交给业务层接管（push ChessRoomPage）。
//
// v2（READY 门）：服务端不再"双人到齐自动 playing"。进入房间后先停在
//   state = "lobby"（准备阶段）—— 本页只显示 loading，随即 push
//   ChessRoomPage，由房间页渲染准备卡片（"准备好了" → "开始游戏"）。
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
import 'chess_room_config_page.dart';
import 'script/chess_script.dart';

/// 社交房间号入口页 —— 单表单 + 双入口（创建/加入）+ 过渡 loading + onStarted。
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

  /// 残局开局快照（建房时服务端消费 → 房间从该局面开始）。
  /// 仅"你创建房间"时生效；"加入房间"路径忽略（join 已存在房间）。
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

  // ——— 输入校验 ———

  /// 房间号合法性：4–6 位大写字母数字，不含易混字符（0/O/1/I/L）。
  static const String _kConfusingChars = '0O1IL';

  String? _validateCode(String code) {
    if (code.length < 4 || code.length > 6) return '房间号为 4–6 位大写字母数字';
    if (code.contains(RegExp('[$_kConfusingChars]'))) {
      return '房间号不能包含 0/O/1/I/L（易混淆）';
    }
    return null;
  }

  /// 校验输入（昵称 + 房间号）；返回 (alias, code) 或 null + 写 _error。
  ({String alias, String code})? _validateAndExtract() {
    final alias = _aliasCtrl.text.trim();
    if (alias.isEmpty) {
      setState(() => _error = '请输入昵称');
      return null;
    }
    final code = _codeCtrl.text.trim().toUpperCase();
    final codeError = _validateCode(code);
    if (codeError != null) {
      setState(() => _error = codeError);
      return null;
    }
    return (alias: alias, code: code);
  }

  // ——— 双入口 ———

  /// 创建房间（host 路径）：push 配置页 → 拿到 cfg → tryJoinOrCreate。
  Future<void> _goAsHost() async {
    final validated = _validateAndExtract();
    if (validated == null) return;
    final alias = validated.alias;
    final code = validated.code;

    // push ChessRoomConfigPage；返回 ChessRoomConfig（用户取消 → null）。
    final cfg = await Navigator.of(context).push<ChessRoomConfig>(
      MaterialPageRoute(
        builder: (_) => ChessRoomConfigPage(
          alias: alias,
          code: code,
          endgame: widget.initialEndgame,
          relayUrl: widget.relayUrl,
          transportBuilder: widget.transportBuilder,
          onSubmit: (cfg) => Navigator.of(context).pop(cfg),
        ),
      ),
    );
    if (cfg == null) return; // 用户取消配置页
    if (!mounted) return;
    await _submitWithConfig(cfg, alias: alias, code: code);
  }

  /// 加入房间（guest 路径）：直接 tryJoinOrCreate。
  /// 服务端 join 路径忽略 initialParams（v5 行为），残局选择不影响。
  Future<void> _goAsGuest() async {
    final validated = _validateAndExtract();
    if (validated == null) return;
    final alias = validated.alias;
    final code = validated.code;
    await _submitWithConfig(null, alias: alias, code: code);
  }

  /// 实际 tryJoinOrCreate。
  ///
  /// cfg = null → guest 路径（initialParams 不带 host_color / first_mover / initial_fen）
  /// cfg != null → host 路径（initialParams 带 host_color + first_mover，残局模式
  ///                  还带 initial_fen；服务端建房时消费这些字段）
  Future<void> _submitWithConfig(
    ChessRoomConfig? cfg, {
    required String alias,
    required String code,
  }) async {
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

      final initialParams = <String, dynamic>{
        'device_id': t.deviceId,
        'alias': alias,
      };

      // host 路径：注入 host_color + first_mover；残局时再带 initial_fen
      if (cfg != null) {
        initialParams['host_color'] = cfg.hostColor;
        // guest_color：'random' 时不带（服务端掷筛决定）；具体值时也带上做冗余校验
        if (cfg.guestColor != null) {
          initialParams['guest_color'] = cfg.guestColor;
        }
        initialParams['first_mover'] = cfg.firstMover;
        final endgame = widget.initialEndgame;
        if (endgame != null) {
          initialParams['initial_fen'] = endgame.fen;
        }
      }
      // guest 路径：initialParams 保持最小（只 device_id + alias）—— 服务端 join
      // 时忽略所有 initialParams（v5 行为）。

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

  /// 入口单表单：昵称 + 房间号 + 残局 chip + 错误 + "创建房间"/"加入房间"。
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
                onSubmitted: (_) => _busy ? null : _goAsGuest(),
              ),
              const SizedBox(height: 4),
              // 残局选择 chip（非 null 时显示；X 清除回标准开局）。
              // 仅"创建房间"路径使用；"加入房间"忽略此选择（服务端 join 时
              // 忽略 initial_fen）。
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
              const SizedBox(height: 20),
              // 双入口按钮（v6）：
              // · "创建房间" → push ChessRoomConfigPage → 用户显式选 host/guest + first_moker
              // · "加入房间" → 直接 tryJoinOrCreate（guest 看不到配置页）
              FilledButton(
                onPressed: _busy ? null : _goAsHost,
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
                        '创建房间',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2,
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : _goAsGuest,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  '加入房间',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // 提示文案（v6 简化）：建/加双入口的角色选择走配置页
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
                        widget.initialEndgame != null
                            ? '残局开局仅在"创建房间"时生效 —— 若对方已用此号建房，'
                                '你点"加入房间"会进入对方的房间。'
                            : '与朋友约定同一房间号："创建房间"是房主，'
                                '"加入房间"是后到者。',
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
            ],
          ),
        ),
      ),
    );
  }
}

enum _ChessLobbyPhase { entry, room }
