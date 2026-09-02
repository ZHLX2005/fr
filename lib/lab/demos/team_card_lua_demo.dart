// lib/lab/demos/team_card_lua_demo.dart
//
// 团建卡牌（v3 Lua 状态机版）— 入口文件
// 组件在 team_card/ 子目录中分文件管理。
//
// 房间生命周期（设计文档 .claude/repo/_self/room-lifecycle-state-machine/）：
//   LobbyEntryPage 创建/加入房间（唯一一次 CreateRoom）
//   → state="setup"：房主走 HostPoolConfigView（SET_* + OPEN 配置现有房间）
//   → state="lobby"：所有人进 PlayingView（waiting 玩家由 OPEN 广播自动入座）
//   → state="playing"：START 发牌；RESET 回 lobby 连续开局

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/net_engine/relay_v3/relay_device_id.dart';
import '../../core/net_engine/relay_v3/relay_v3_transport.dart'
    show RelayV3Transport, RelayV3Exception;
import '../../core/surround_game/board_theme.dart';
import '../../services/lua/lua_game_alias.dart';
import '../lab_container.dart';
import 'team_card/constants.dart';
import 'team_card/engine.dart'
    show RoomHandle, TeamCardRoom, myIsHost;
import 'team_card/widgets.dart' show SetupPage, PlayingView;

// ══════════════════════════════════════════════════════════════
// Demo 注册
// ══════════════════════════════════════════════════════════════

class TeamCardLuaDemo extends DemoPage {
  TeamCardLuaDemo();
  @override String get title => '团建卡牌（联机）';
  @override String get slug => 'team-card-lua';
  @override String get description => '谁是卧底/狼人杀 · Lua 服务端权威 + 三区大厅';
  @override bool get preferFullScreen => true;
  @override DemoType get type => DemoType.game;
  @override Widget buildPage(BuildContext context) => const _TeamCardLuaDemoPage();
}

void registerTeamCardLuaDemo() => demoRegistry.register(TeamCardLuaDemo());

// ══════════════════════════════════════════════════════════════
// 主页面（房间入口 + 房主配置 + 游戏中）
// ══════════════════════════════════════════════════════════════

class _TeamCardLuaDemoPage extends StatefulWidget {
  const _TeamCardLuaDemoPage();
  @override
  State<_TeamCardLuaDemoPage> createState() => _TeamCardLuaDemoPageState();
}

class _TeamCardLuaDemoPageState extends State<_TeamCardLuaDemoPage> {
  /// 'entry' = 入口表单；'host_setup' = 房主配置（setup 态）；'playing' = 房间内
  String _phase = 'entry';
  RoomHandle? _handle;

  @override
  void dispose() {
    _handle?.dispose();
    super.dispose();
  }

  void _onJoined(RoomHandle handle) => setState(() {
        _handle = handle;
        _phase = 'playing';
      });

  void _onHostNeedsConfig() => setState(() => _phase = 'host_setup');

  /// 配置完成（或跳过）：同一房间，直接切到房间视图。
  /// 房间只创建一次（LobbyEntryPage），这里不换 handle。
  void _onHostConfigDone() => setState(() => _phase = 'playing');

  Future<void> _disconnect() async {
    final h = _handle;
    setState(() {
      _handle = null;
      _phase = 'entry';
    });
    if (h != null) await h.leave();
  }

  @override
  Widget build(BuildContext context) {
    final handle = _handle;
    // 棋盘主题暖色（与其他 Lua 游戏入口同款配色）
    final theme = BoardTheme.of(context);
    final bg = theme.boardSurface;
    final panelText = theme.btnText;
    if (handle == null) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          title: const Text('团建卡牌（联机）'),
          backgroundColor: bg,
          foregroundColor: panelText,
          elevation: 0,
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 16),
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
                  padding: EdgeInsets.fromLTRB(24, 24, 24, 24),
                  child: LobbyEntryPage(
                    onJoined: _onJoined,
                    onHostNeedsConfig: _onHostNeedsConfig,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (_phase == 'host_setup') {
      return Scaffold(
        appBar: AppBar(title: const Text('团建卡牌（联机）')),
        body: HostPoolConfigView(
          handle: handle,
          onDone: _onHostConfigDone,
          onLeave: _disconnect,
        ),
      );
    }
    return Scaffold(
      // 房间内：内层视图（身份卡/主持/旁观/等待页）自带唯一返回按钮（走 onLeave
      // 正确离开语义），外层 AppBar 不再自动加 leading，避免左上角双返回键
      appBar: AppBar(
        title: const Text('团建卡牌（联机）'),
        automaticallyImplyLeading: false,
      ),
      body: PlayingView(
        handle: handle,
        onLeave: _disconnect,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Lobby Entry Page（社交房间号：alias + code → tryJoinOrCreate）
// ══════════════════════════════════════════════════════════════

class LobbyEntryPage extends StatefulWidget {
  const LobbyEntryPage({
    super.key,
    required this.onJoined,
    required this.onHostNeedsConfig,
  });
  final void Function(RoomHandle handle) onJoined;
  final VoidCallback onHostNeedsConfig;

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
    // 全局共享 alias（与 gomoku/围棋/象棋 等所有 Lua 房间游戏同步）
    final v = LuaGameAlias.value;
    if (v.isNotEmpty) _aliasCtrl.text = v;
    LuaGameAlias.notifier.addListener(_onAliasChanged);
  }

  @override
  void dispose() {
    LuaGameAlias.notifier.removeListener(_onAliasChanged);
    _aliasCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  void _onAliasChanged() {
    if (!mounted) return;
    final v = LuaGameAlias.value;
    if (v.isNotEmpty && _aliasCtrl.text != v) {
      _aliasCtrl.text = v;
    }
  }

  String _normalizeCode(String s) => s.trim().toUpperCase();

  /// 生成 4 位易读房间号（排除 0/O/1/I/L）——仅供"懒得想号"的房主一键填入，
  /// 输入框内容仍是最终房间号（后端 requested_code 语义）。
  String _randomCode() {
    const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final r = DateTime.now().millisecondsSinceEpoch;
    final buf = StringBuffer();
    int seed = r;
    for (int i = 0; i < 4; i++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      buf.write(chars[seed % chars.length]);
    }
    return buf.toString();
  }

  Future<void> _go() async {
    final alias = _aliasCtrl.text.trim().isEmpty ? '玩家' : _aliasCtrl.text.trim();
    final code = _normalizeCode(_codeCtrl.text);
    final rx = RegExp(r'^[A-Z0-9]{4,6}$');
    if (!rx.hasMatch(code)) {
      setState(() => _error = '房间号 4-6 位大写字母+数字');
      return;
    }
    await LuaGameAlias.save(alias);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = RelayV3Transport(
        relayUrl: kTeamCardRelayUrl,
        alias: alias,
        deviceId: await RelayDeviceId.get(),
      );
      // 房间只创建这一次；玩家区人数/身份池由房主在 setup 阶段配置
      final h = await TeamCardRoom.tryJoinOrCreate(t, code: code, alias: alias);
      if (!mounted) return;
      widget.onJoined(h);
      // 服务端权威：创建者（第一个输入未存在号码的人）→ 进配置页
      if (myIsHost(h.latest, t.deviceId) && h.latest?.state == 'setup') {
        widget.onHostNeedsConfig();
      }
    } catch (e) {
      if (!mounted) return;
      String msg = '$e';
      if (e is RelayV3Exception) {
        final body = e.body.toLowerCase();
        if (e.statusCode == 409 && body.contains('code collision')) {
          msg = '房间号 $code 已被占用，请换一个';
        } else if (e.statusCode == 409 && body.contains('join rejected')) {
          msg = '房间已满（8 人上限），无法加入';
        } else if (e.statusCode == 404) {
          msg = '房间号 $code 不存在且创建失败';
        } else {
          msg = '进入失败（${e.statusCode}）';
        }
      }
      setState(() {
        _busy = false;
        _error = msg;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = BoardTheme.of(context);
    // 圆角浅底输入框（聚焦时边框变粗变深）——与其他 Lua 游戏入口同款
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
        decoration: inputDec('昵称'),
        style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w500, color: theme.btnText),
        textAlignVertical: TextAlignVertical.center,
        onChanged: (v) => LuaGameAlias.save(v.trim()),
      ),
      SizedBox(height: 12),

      // ── 房间号 ──
      TextField(
        controller: _codeCtrl,
        decoration: inputDec('房间号（4–6 位大写字母数字）').copyWith(
          suffixIcon: IconButton(
            icon: Icon(Icons.casino_outlined,
                size: 20, color: theme.btnSub.withValues(alpha: 0.8)),
            tooltip: '随机生成房间号（我是房主）',
            onPressed:
                _busy ? null : () => setState(() => _codeCtrl.text = _randomCode()),
          ),
        ),
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: theme.btnText,
          letterSpacing: 2,
        ),
        keyboardType: TextInputType.text,
        textCapitalization: TextCapitalization.characters,
        maxLength: 6,
        onSubmitted: (_) => _busy ? null : _go(),
      ),
      SizedBox(height: 12),

      // ── 提示行（浅灰块，左对齐）──
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
              '输入同一号码即可开局，谁先到谁是房主；房主配置后其他人自动入座',
              style: TextStyle(color: theme.btnSub, fontSize: 12, height: 1.4),
            ),
          ),
        ]),
      ),

      // ── 错误提示（暖红浅块）──
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
              child: Text('◉',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12)),
            ),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                _error!,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                    height: 1.4),
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
// Host Pool Config View（房主配置现有房间：SET_* + OPEN）
// 包一层 SetupPage（角色池编辑器复用）+ 跳过按钮
// ══════════════════════════════════════════════════════════════

class HostPoolConfigView extends StatelessWidget {
  const HostPoolConfigView({
    super.key,
    required this.handle,
    required this.onDone,
    required this.onLeave,
  });
  final RoomHandle handle;
  final VoidCallback onDone;
  final Future<void> Function() onLeave;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      SetupPage(
        initialRoles: [
          RoleDef(label: '卧底', count: 1),
          RoleDef(label: '平民', count: 5),
        ],
        handle: handle,
        onStarted: (h, _) => onDone(),
      ),
      Positioned(
        top: 8,
        right: 8,
        child: IconButton(
          icon: Icon(Icons.skip_next),
          tooltip: '用默认配置直接开放房间',
          onPressed: () async {
            // 跳过详细配置：用默认池开放（waiting 玩家仍会自动入座）
            try {
              await TeamCardRoom(handle).open();
            } catch (_) {
              // best-effort：OPEN 失败也能进房间视图看现场
            }
            onDone();
          },
        ),
      ),
    ]);
  }
}