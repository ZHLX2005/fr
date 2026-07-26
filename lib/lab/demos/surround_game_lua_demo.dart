// lib/lab/demos/surround_game_lua_demo.dart
// 围追堵截（Quoridor）互联网双人对战 — v3 Lua 状态机版
//
// 流程：
//   房主创建房间 → 玩家输入码加入 → 双方 ACK → 房主点开始 → playing → 交替 MOVE
//
// 镜像策略：
//   - 服务端存规范坐标（host=top=y0, guest=bottom=y8）
//   - host 端 y 方向翻转后渲染（host 自身在下方）
//   - guest 端直接渲染（guest 自身在下方）
//   - 触摸坐标也相应翻转

import 'package:flutter/material.dart';
import '../lab_container.dart';
import 'package:xiaodouzi_fr/core/surround_game/board_theme.dart';
import 'surround_game_lua/engine.dart' show RoomHandle;
import 'surround_game_lua/widgets.dart' show SetupPage, JoinPage, OnlineGamePage;

// ══════════════════════════════════════════════════════════════
// Demo 注册
// ══════════════════════════════════════════════════════════════

class SurroundGameLuaDemo extends DemoPage {
  SurroundGameLuaDemo();
  @override String get title => '围追堵截（Lua）';
  @override String get slug => 'surround-game-lua';
  @override String get description => 'Quoridor 互联网双人对战 · Lua 服务端权威棋谱';
  @override bool get preferFullScreen => true;
  // 归属游戏中心（联机 · 棋游），不再出现在 Lab 列表
  @override DemoType get type => DemoType.game;
  @override Widget buildPage(BuildContext context) => const SurroundGameLuaPage();
}

void registerSurroundGameLuaDemo() => demoRegistry.register(SurroundGameLuaDemo());

// ══════════════════════════════════════════════════════════════
// 主页面
// ══════════════════════════════════════════════════════════════

class SurroundGameLuaPage extends StatefulWidget {
  const SurroundGameLuaPage({super.key});
  @override State<SurroundGameLuaPage> createState() => _SurroundGameLuaPageState();
}

class _SurroundGameLuaPageState extends State<SurroundGameLuaPage> {
  RoomHandle? _handle;
  bool _isMaster = true;
  bool _isHostSide = false;

  @override
  void dispose() { _handle?.dispose(); super.dispose(); }
  void _onCreated(RoomHandle h) => setState(() { _handle = h; _isHostSide = true; });
  void _onJoined(RoomHandle h)  => setState(() { _handle = h; _isHostSide = false; });
  Future<void> _disconnect() async {
    final h = _handle;
    setState(() => _handle = null);
    if (h != null) await h.leave();
  }

  @override
  Widget build(BuildContext context) {
    // 用棋盘主题色（暖色 BoardTheme.warm），避免一进 demo 就纯黑、与游戏内色调脱节
    final theme = BoardTheme.of(context);
    final bg = theme.boardSurface;
    final panelText = theme.btnText;
    if (_handle != null) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          title: const Text('围追堵截'),
          backgroundColor: bg,
          foregroundColor: panelText,
          elevation: 0,
        ),
        body: OnlineGamePage(
          handle: _handle!, isHostSide: _isHostSide, onLeave: _disconnect,
        ),
      );
    }
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('围追堵截'),
        backgroundColor: bg,
        foregroundColor: panelText,
        elevation: 0,
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true,  label: Text('建房')),
              ButtonSegment(value: false, label: Text('加入')),
            ],
            selected: {_isMaster},
            onSelectionChanged: (s) => setState(() => _isMaster = s.first),
          ),
        ),
        Expanded(child: _isMaster ? SetupPage(onCreated: _onCreated) : JoinPage(onJoined: _onJoined)),
      ]),
    );
  }
}
