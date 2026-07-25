// lib/lab/demos/team_card_lua_demo.dart
//
// 团建卡牌（v3 Lua 状态机版）— 入口文件
// 组件在 team_card/ 子目录中分文件管理。

import 'dart:async';

import 'package:flutter/material.dart';

import '../lab_container.dart';
import 'team_card/constants.dart';
import 'team_card/engine.dart' show RoomHandle;
import 'team_card/widgets.dart' show SetupPage, JoinPage, PlayingView;

// ══════════════════════════════════════════════════════════════
// Demo 注册
// ══════════════════════════════════════════════════════════════

class TeamCardLuaDemo extends DemoPage {
  TeamCardLuaDemo();
  @override String get title => '团建卡牌 v3';
  @override String get slug => 'team-card-lua';
  @override String get description => '谁是卧底/狼人杀 · Lua 服务端权威 + 准备门';
  @override bool get preferFullScreen => true;
  @override Widget buildPage(BuildContext context) => const _TeamCardLuaDemoPage();
}

void registerTeamCardLuaDemo() => demoRegistry.register(TeamCardLuaDemo());

// ══════════════════════════════════════════════════════════════
// 主页面
// ══════════════════════════════════════════════════════════════

class _TeamCardLuaDemoPage extends StatefulWidget {
  const _TeamCardLuaDemoPage();
  @override State<_TeamCardLuaDemoPage> createState() => _TeamCardLuaDemoPageState();
}

class _TeamCardLuaDemoPageState extends State<_TeamCardLuaDemoPage> {
  bool _isMaster = true;
  RoomHandle? _handle;
  int? _hostCapacity;

  @override
  void dispose() {
    _handle?.dispose();
    super.dispose();
  }

  void _onStarted(RoomHandle handle, int capacity) => setState(() {
    _handle = handle;
    _hostCapacity = capacity;
  });

  Future<void> _disconnect() async {
    final h = _handle;
    setState(() {
      _handle = null;
      _hostCapacity = null;
    });
    if (h != null) await h.leave();
  }

  @override
  Widget build(BuildContext context) {
    if (_handle != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('团建卡牌 v3')),
        body: PlayingView(
          handle: _handle!,
          hostCapacity: _hostCapacity ?? 0,
          onLeave: _disconnect,
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('团建卡牌 v3')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('我是房主')),
                ButtonSegment(value: false, label: Text('我是玩家')),
              ],
              selected: {_isMaster},
              onSelectionChanged: (s) => setState(() => _isMaster = s.first),
            ),
          ),
          Expanded(
            child: _isMaster
                ? SetupPage(
                    initialRoles: [RoleDef(label: '卧底', count: 1), RoleDef(label: '平民', count: 5)],
                    onStarted: _onStarted,
                  )
                : JoinPage(onStarted: _onStarted),
          ),
        ],
      ),
    );
  }
}
