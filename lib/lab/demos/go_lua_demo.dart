// lib/lab/demos/go_lua_demo.dart
// 联机围棋（Go）互联网双人对战 — v3 Lua 状态机版
//
// 流程：
//   玩家输入昵称 + 房间码 → 点击"进入对局"
//   → 服务端 join 尝试：404 → 用此号创建新房间
//   → 双方均进入后 ACK × 2 → 自动进入 playing
//   → 服务端权威算落子（提子/打劫/自杀），客户端纯渲染
//   → 双方连过 → 数子终局

import 'package:flutter/material.dart';
import '../lab_container.dart';
import 'package:xiaodouzi_fr/core/surround_game/board_theme.dart';
import 'go_lua/go_engine.dart' show RoomHandle;
import 'go_lua/widgets.dart' show LobbyEntryPage, OnlineGamePage;

// ══════════════════════════════════════════════════════════════
// Demo 注册
// ══════════════════════════════════════════════════════════════

class GoLuaDemo extends DemoPage {
  GoLuaDemo();
  @override String get title => '围棋（联机）';
  @override String get slug => 'go-lua';
  @override String get description => 'Go 互联网双人对战 · Lua 服务端权威棋谱';
  @override bool get preferFullScreen => true;
  @override DemoType get type => DemoType.game;
  @override Widget buildPage(BuildContext context) => const GoLuaPage();
}

void registerGoLuaDemo() => demoRegistry.register(GoLuaDemo());

// ══════════════════════════════════════════════════════════════
// 主页面
// ══════════════════════════════════════════════════════════════

class GoLuaPage extends StatefulWidget {
  const GoLuaPage({super.key});
  @override State<GoLuaPage> createState() => _GoLuaPageState();
}

class _GoLuaPageState extends State<GoLuaPage> {
  RoomHandle? _handle;

  @override
  void dispose() {
    _handle?.dispose();
    super.dispose();
  }

  void _onJoined(RoomHandle h) => setState(() => _handle = h);
  Future<void> _disconnect() async {
    final h = _handle;
    setState(() => _handle = null);
    if (h != null) await h.leave();
  }

  @override
  Widget build(BuildContext context) {
    final theme = BoardTheme.of(context);
    final bg = theme.boardSurface;
    final panelText = theme.btnText;
    if (_handle != null) {
      return Scaffold(
        backgroundColor: bg,
        body: OnlineGamePage(handle: _handle!, onLeave: _disconnect),
      );
    }
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('围棋（联机）'),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: theme.panelBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: theme.panelBorder),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
                          blurRadius: 16, offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    padding: EdgeInsets.fromLTRB(24, 24, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [LobbyEntryPage(onJoined: _onJoined)],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
