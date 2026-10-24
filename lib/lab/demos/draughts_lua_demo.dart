// lib/lab/demos/draughts_lua_demo.dart
//
// 国际跳棋（International Draughts 10×10）互联网双人对战 — v3 Lua 状态机版。
//
// 流程（smartMatch 单入口）：
//   输入昵称 + 房间号 →「进入对局」（tryJoinOrCreate：先到 = 房主）
//   → DraughtsRoomPage：双方 ACK → host DEAL → 走子 / 吃子链 / 升王
//   → 终局由客户端引擎判定后 CLAIM_END；host 可 RESET 再来一局
//
// 不做本地 / AI；皮肤本期不做（棋盘走主题色）。

import 'package:flutter/material.dart';

import '../lab_container.dart';
import '../../core/draughts/lobby/draughts_lobby_spec.dart';
import '../../core/draughts/p2p/draughts_room_page.dart';
import '../../core/ui/game/game_lobby_page.dart';
import '../../core/game_kit/lobby/game_lobby_slots.dart';
import '../../core/game_kit/lobby/game_lobby_spec.dart' show LobbyStartedCtx;
import '../../core/net_engine/relay_v3/relay_v3_transport.dart' show RoomHandle;

// ══════════════════════════════════════════════════════════════
// Demo 注册
// ══════════════════════════════════════════════════════════════

class DraughtsLuaDemo extends DemoPage {
  DraughtsLuaDemo();

  @override
  String get title => '国际跳棋（联机）';

  @override
  String get slug => 'draughts-lua';

  @override
  String get description =>
      'International Draughts 10×10 · Lua 服务端权威棋谱 · 强制吃子 + flying king';

  @override
  bool get preferFullScreen => true;

  @override
  DemoType get type => DemoType.game;

  @override
  Widget buildPage(BuildContext context) => const DraughtsLuaPage();
}

void registerDraughtsLuaDemo() => demoRegistry.register(DraughtsLuaDemo());

// ══════════════════════════════════════════════════════════════
// 主页面
// ══════════════════════════════════════════════════════════════

class DraughtsLuaPage extends StatefulWidget {
  const DraughtsLuaPage({super.key});

  @override
  State<DraughtsLuaPage> createState() => _DraughtsLuaPageState();
}

class _DraughtsLuaPageState extends State<DraughtsLuaPage> {
  /// 大厅页 key：对弈页 pop 后调用 resetToEntry 回到入口表单。
  final GlobalKey<GameLobbyPageState> _lobbyKey =
      GlobalKey<GameLobbyPageState>();

  /// 对弈页句柄（dispose 时清理）。
  RoomHandle? _activeHandle;

  /// 进入对局：push DraughtsRoomPage；pop 后 resetToEntry。
  Future<void> _onStarted(RoomHandle handle, LobbyStartedCtx ctx) async {
    _activeHandle = handle;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DraughtsRoomPage(
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
      spec: kDraughtsLobbySpec,
      slots: const GameLobbySlots(),
      onStarted: _onStarted,
    );
  }
}
