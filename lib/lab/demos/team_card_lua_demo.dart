// lib/lab/demos/team_card_lua_demo.dart
//
// 团建卡牌（v3 Lua 状态机版）— 入口文件
// 组件在 team_card/ 子目录中分文件管理。
//
// 房间生命周期（设计文档 .claude/repo/_self/room-lifecycle-state-machine/）：
//   GameLobbyPage 创建/加入房间（唯一一次 CreateRoom）
//   → state="setup"：房主走 HostPoolConfigView（SET_* + OPEN 配置现有房间）
//   → state="lobby"：所有人进 PlayingView（waiting 玩家由 OPEN 广播自动入座）
//   → state="playing"：START 发牌；RESET 回 lobby 连续开局
//
// 形态特殊点：
//   · kTeamCardLobbySpec.copy.randomCodeEnabled = true —— _lobby_form 内置随机号按钮
//   · slots.onStartedExtras 注入 ctx.extras['needsConfig'] ——
//     snapshot 服务端权威判断「我是 host 且 state==setup」
//   · _onStarted 读 ctx.extras['needsConfig'] 决定 phase 进 host_setup 还是 playing

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/game_kit/lobby/game_lobby_page.dart';
import '../../core/game_kit/lobby/game_lobby_slots.dart';
import '../../core/game_kit/lobby/game_lobby_spec.dart';
import '../../core/team_card/lobby/team_card_lobby_spec.dart';
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

  /// GameLobbyPage 回调：服务端权威判断 → 决定进 host_setup 还是直接 playing。
  ///
  /// slots.onStartedExtras 已基于 snapshot + deviceId 写入 ctx.extras['needsConfig']：
  ///   · host + state=='setup' → true  → 进 HostPoolConfigView（SET_* + OPEN）
  ///   · 否则 → false                    → 直接进 PlayingView（lobby 等待房）
  void _onStarted(RoomHandle handle, LobbyStartedCtx ctx) {
    final needsConfig = ctx.extras['needsConfig'] == true;
    setState(() {
      _handle = handle;
      _phase = needsConfig ? 'host_setup' : 'playing';
    });
  }

  /// 配置完成（或跳过）：同一房间，直接切到房间视图。
  /// 房间只创建一次（GameLobbyPage），这里不换 handle。
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
    if (handle == null) {
      // 入口表单：GameLobbyPage 自带 Scaffold + AppBar + 主题适配
      return GameLobbyPage(
        spec: kTeamCardLobbySpec,
        slots: const GameLobbySlots(
          // 服务端权威「我是 host 且 state=='setup'」→ 进 SetupPage 配置页
          onStartedExtras: _injectHostNeedsConfig,
        ),
        onStarted: _onStarted,
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

  /// slots.onStartedExtras 实现：基于 snapshot 服务端权威判断
  /// 「我是房主（deviceId == snapshot.context['host_id']）且房间 state=='setup'」
  /// → 写入 ctx.extras['needsConfig'] = true，demo 端 _onStarted 据此切换 phase。
  ///
  /// 注意：handler 在 GameLobbyPage._goSmartMatch 里 tryJoinOrCreate 成功之后
  /// 立即调用，handle.latest 在 transport.createRoom/tryJoinOrCreate 返回时已赋值。
  static void _injectHostNeedsConfig(LobbyStartedCtx ctx, RoomHandle handle) {
    final isHost = myIsHost(handle.latest, handle.transport.deviceId);
    final stateSetup = handle.latest?.state == 'setup';
    if (isHost && stateSetup) {
      ctx.extras['needsConfig'] = true;
    }
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
