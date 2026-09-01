// lib/lab/demos/team_card_lua_demo.dart
//
// 团建卡牌（v3 Lua 状态机版）— 入口文件
// 组件在 team_card/ 子目录中分文件管理。
//
// 入口模式：社交房间号（tryJoinOrCreate）—— 第一个输入未存在房间号的人自动成为房主
// 参考 chess_lobby_page.dart 的 `chess_lobby_page.dart:277-416` 入口模板。
// 房主进房后先走 HostPoolConfigView 上传角色池，再进入 PlayingView。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/net_engine/relay_v3/relay_device_id.dart';
import '../../core/net_engine/relay_v3/relay_v3_transport.dart'
    show RelayV3Transport, RelayV3Exception;
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
  @override
  String get title => '团建卡牌（联机）';
  @override
  String get slug => 'team-card-lua';
  @override
  String get description => '谁是卧底/狼人杀 · Lua 服务端权威 + 准备门';
  @override
  bool get preferFullScreen => true;
  @override
  DemoType get type => DemoType.game;
  @override
  Widget buildPage(BuildContext context) => const _TeamCardLuaDemoPage();
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
  /// 'entry' = 入口表单；'host_setup' = 房主配置角色池；'playing' = 进入房间
  String _phase = 'entry';
  RoomHandle? _handle;
  int _playerSlots = 6;

  @override
  void dispose() {
    _handle?.dispose();
    super.dispose();
  }

  void _onJoined(RoomHandle handle, int playerSlots) => setState(() {
        _handle = handle;
        _playerSlots = playerSlots;
        _phase = 'playing';
      });

  void _onHostNeedsConfig() => setState(() => _phase = 'host_setup');

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
    if (_phase == 'playing' && _handle != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('团建卡牌（联机）')),
        body: PlayingView(
          handle: _handle!,
          hostCapacity: _playerSlots,
          onLeave: _disconnect,
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('团建卡牌（联机）')),
      body: _phase == 'host_setup' && _handle != null
          ? HostPoolConfigView(
              handle: _handle!,
              onDone: _onHostConfigDone,
              onLeave: _disconnect,
            )
          : LobbyEntryPage(
              initialPlayerSlots: _playerSlots,
              onJoined: _onJoined,
              onHostNeedsConfig: _onHostNeedsConfig,
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
    required this.initialPlayerSlots,
    required this.onJoined,
    required this.onHostNeedsConfig,
  });
  final int initialPlayerSlots;
  final void Function(RoomHandle handle, int playerSlots) onJoined;
  final VoidCallback onHostNeedsConfig;

  @override
  State<LobbyEntryPage> createState() => _LobbyEntryPageState();
}

class _LobbyEntryPageState extends State<LobbyEntryPage> {
  final _aliasCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _busy = false;
  String? _error;
  int _playerSlots = 6;

  @override
  void initState() {
    super.initState();
    _playerSlots = widget.initialPlayerSlots;
    AliasPrefs.load().then((v) {
      if (mounted && v.isNotEmpty) setState(() => _aliasCtrl.text = v);
    });
  }

  @override
  void dispose() {
    _aliasCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  String _normalizeCode(String s) => s.trim().toUpperCase();

  /// 生成 4 位易读房间号（排除 0/O/1/I/L）
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
    await AliasPrefs.save(alias);
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
      final h = await TeamCardRoom.tryJoinOrCreate(
        t,
        code: code,
        playerSlots: _playerSlots,
        spectatorSlots: 0, // 0 = 无限旁观
        alias: alias,
      );
      if (!mounted) return;
      // 服务端权威：检查 host_id 是否是我；是则进入 host_setup（配置角色池）
      // 否则直接进入 PlayingView
      final isHost = myIsHost(h.latest, t.deviceId);
      widget.onJoined(h, _playerSlots);
      if (isHost) {
        widget.onHostNeedsConfig();
      }
    } catch (e) {
      if (!mounted) return;
      // 409/404 错误映射
      String msg = '$e';
      final codeStr = code;
      if (e is RelayV3Exception) {
        final body = e.body.toLowerCase();
        if (e.statusCode == 409 && body.contains('code collision')) {
          msg = '房间号 $codeStr 已被占用，请换一个';
        } else if (e.statusCode == 409 && body.contains('join rejected')) {
          msg = '房间 $codeStr 已满员，无法加入';
        } else if (e.statusCode == 404) {
          msg = '房间号 $codeStr 不存在且创建失败';
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
    final theme = Theme.of(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(32, 24, 32, 32),
      children: [
        Icon(Icons.workspace_premium,
            size: 56, color: Colors.amber.shade600.withValues(alpha: 0.85)),
        SizedBox(height: 12),
        Text('团建卡牌',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        SizedBox(height: 6),
        Text('输入同一号码即可对战，谁先到谁是房主',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline)),
        SizedBox(height: 28),
        TextField(
          controller: _aliasCtrl,
          decoration: InputDecoration(
            labelText: '你的名字',
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        SizedBox(height: 14),
        TextField(
          controller: _codeCtrl,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: '房间号',
            hintText: '4-6 位大写字母+数字',
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixIcon: Icon(Icons.tag),
            suffixIcon: IconButton(
              icon: Icon(Icons.casino_outlined),
              tooltip: '随机生成房间号（我是房主）',
              onPressed: _busy
                  ? null
                  : () => setState(() => _codeCtrl.text = _randomCode()),
            ),
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
            LengthLimitingTextInputFormatter(6),
          ],
          style: TextStyle(letterSpacing: 4, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 12),
        Row(children: [
          Icon(Icons.people,
              size: 18, color: theme.colorScheme.outline),
          SizedBox(width: 8),
          Text('玩家人数',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500)),
          Spacer(),
          IconButton(
            onPressed: _busy || _playerSlots <= 2
                ? null
                : () => setState(() => _playerSlots--),
            icon: Icon(Icons.remove_circle_outline),
          ),
          Text('$_playerSlots',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          IconButton(
            onPressed: _busy || _playerSlots >= 12
                ? null
                : () => setState(() => _playerSlots++),
            icon: Icon(Icons.add_circle_outline),
          ),
        ]),
        if (_error != null)
          Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(_error!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
          ),
        SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _go,
          icon: _busy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Icon(Icons.login),
          label: Text(_busy ? '进入中…' : '进入对局'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
            backgroundColor: Colors.amber.shade700,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Host Pool Config View（房主上传身份池后进入 PlayingView）
// 复用 SetupPage 的角色池编辑逻辑
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
        onStarted: (h, capacity) {
          // 进房即关闭配置页（SetupPage 是过渡页）
          onDone();
        },
      ),
      Positioned(
        top: 8,
        right: 8,
        child: IconButton(
          icon: Icon(Icons.skip_next),
          tooltip: '使用默认池直接开始',
          onPressed: onDone,
        ),
      ),
    ]);
  }
}