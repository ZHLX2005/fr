// lib/lab/demos/go_lua_demo.dart
// 联机围棋（Go）互联网双人对战 — v3 Lua 状态机版
//
// 流程：
//   玩家输入昵称 + 房间码 → 点击"进入对局"
//   → 服务端 join 尝试：404 → 用此号创建新房间
//   → 双方均进入后 ACK × 2 → 自动进入 playing
//   → 服务端权威算落子（提子/打劫/自杀），客户端纯渲染
//   → 双方连过 → 数子终局
//
// 入口迁移：原 LobbyEntryPage（lib/lab/demos/go_lua/widgets.dart）
//   → GameLobbyPage + kGoLobbySpec（lib/core/go/lobby/go_lobby_spec.dart）。

import 'package:flutter/material.dart';
import '../lab_container.dart';
import 'go_lua/go_engine.dart' show RoomHandle;
import 'go_lua/widgets.dart' show OnlineGamePage;
import '../../core/game_kit/lobby/game_lobby_page.dart';
import '../../core/game_kit/lobby/game_lobby_slots.dart';
import '../../core/game_kit/lobby/game_lobby_spec.dart' show LobbyStartedCtx;
import '../../core/go/lobby/go_lobby_spec.dart';

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
  /// 大厅页 key：对弈页 pop 后调用 resetToEntry 回到入口表单。
  final GlobalKey<GameLobbyPageState> _lobbyKey =
      GlobalKey<GameLobbyPageState>();

  /// 对弈页句柄（dispose 时清理）。
  RoomHandle? _activeHandle;

  /// 进入对局：push OnlineGamePage；pop 后 resetToEntry。
  Future<void> _onStarted(RoomHandle handle, LobbyStartedCtx ctx) async {
    _activeHandle = handle;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OnlineGamePage(
          handle: handle,
          onLeave: () async {
            await handle.leave();
          },
        ),
      ),
    );
    _activeHandle = null;
    if (!mounted) return;
    _lobbyKey.currentState?.exposed.resetToEntry();
  }

  @override
  void dispose() {
    _activeHandle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GameLobbyPage(
      key: _lobbyKey,
      spec: kGoLobbySpec,
      slots: const GameLobbySlots(),
      onStarted: _onStarted,
    );
  }
}