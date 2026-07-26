// lib/lab/demos/gomoku_lua_demo.dart
// 五子棋（Gomoku）互联网双人对战 — v3 Lua 状态机版
//
// 流程：
//   房主创建房间 → 玩家输入码加入 → 双方 ACK → 房主点开始 → playing → 交替落子
//
// 与围追堵截的差异：
//   - 15x15 对称棋盘，落子在交点
//   - 无镜像翻转（对称棋盘）
//   - 角色 black_player_id（host=黑先手）
//   - 胜负 = 连五，客户端本地判定后发 WIN

import 'package:flutter/material.dart';
import '../lab_container.dart';
import 'package:xiaodouzi_fr/core/surround_game/board_theme.dart';
import 'gomoku_lua/engine.dart' show RoomHandle;
import 'gomoku_lua/widgets.dart' show SetupPage, JoinPage, OnlineGamePage;

// ══════════════════════════════════════════════════════════════
// Demo 注册
// ══════════════════════════════════════════════════════════════

class GomokuLuaDemo extends DemoPage {
  GomokuLuaDemo();
  @override String get title => '五子棋（Lua）';
  @override String get slug => 'gomoku-lua';
  @override String get description => 'Gomoku 互联网双人对战 · Lua 服务端权威棋谱';
  @override bool get preferFullScreen => true;
  // 归属游戏中心（联机 · 棋游），不再出现在 Lab 列表
  @override DemoType get type => DemoType.game;
  @override Widget buildPage(BuildContext context) => const GomokuLuaPage();
}

void registerGomokuLuaDemo() => demoRegistry.register(GomokuLuaDemo());

// ══════════════════════════════════════════════════════════════
// 主页面
// ══════════════════════════════════════════════════════════════

class GomokuLuaPage extends StatefulWidget {
  const GomokuLuaPage({super.key});
  @override State<GomokuLuaPage> createState() => _GomokuLuaPageState();
}

class _GomokuLuaPageState extends State<GomokuLuaPage> {
  RoomHandle? _handle;
  bool _isMaster = true;

  @override
  void dispose() { _handle?.dispose(); super.dispose(); }
  void _onCreated(RoomHandle h) => setState(() => _handle = h);
  void _onJoined(RoomHandle h)  => setState(() => _handle = h);
  Future<void> _disconnect() async {
    final h = _handle;
    setState(() => _handle = null);
    if (h != null) await h.leave();
  }

  @override
  Widget build(BuildContext context) {
    // 用棋盘主题色（暖色），与游戏内色调一致
    final theme = BoardTheme.of(context);
    final bg = theme.boardSurface;
    final panelText = theme.btnText;
    if (_handle != null) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          title: const Text('五子棋'),
          backgroundColor: bg,
          foregroundColor: panelText,
          elevation: 0,
        ),
        body: OnlineGamePage(handle: _handle!, onLeave: _disconnect),
      );
    }
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('五子棋'),
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
