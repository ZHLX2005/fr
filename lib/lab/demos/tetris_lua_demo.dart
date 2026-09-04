// lib/lab/demos/tetris_lua_demo.dart
// 俄罗斯方块（Tetris）互联网双人对战 — v3 Lua 状态机版
//
// 与五子棋/围追堵截（回合制）的本质差异：双方各自本地实时玩，
// 服务端只下发共享方块序列 + 广播双方堆积状态/分数。非回合制。
//
// UI 规范（versus-game-room-template v2026-07-26）：
//   - 单表单智能匹配：昵称 + 房间号 + 「进入对局」→ tryJoinOrCreate
//   - 谁先到谁是房主；服务端 host_id 权威
//   - lobby / ready 同一张卡片，按钮三态原地切换（准备好了 / 已准备 / 开始游戏）
//
// 入口迁移：原 LobbyEntryPage（lib/lab/demos/tetris_lua/widgets.dart）
//   → GameLobbyPage + kTetrisLobbySpec（lib/core/tetris/lobby/tetris_lobby_spec.dart）。

import 'package:flutter/material.dart';
import '../lab_container.dart';
import 'tetris_lua/engine.dart' show RoomHandle;
import 'tetris_lua/widgets.dart' show OnlineGamePage;
import '../../core/game_kit/lobby/game_lobby_page.dart';
import '../../core/game_kit/lobby/game_lobby_slots.dart';
import '../../core/game_kit/lobby/game_lobby_spec.dart' show LobbyStartedCtx;
import '../../core/tetris/lobby/tetris_lobby_spec.dart';

// ══════════════════════════════════════════════════════════════
// Demo 注册
// ══════════════════════════════════════════════════════════════

class TetrisLuaDemo extends DemoPage {
  TetrisLuaDemo();
  @override
  String get title => '俄罗斯方块（联机）';
  @override
  String get slug => 'tetris-lua';
  @override
  String get description => 'Tetris 互联网双人对战 · 共享序列 + 实时比拼';
  @override
  bool get preferFullScreen => true;
  // 归属游戏中心（联机 · 街机），不再出现在 Lab 列表
  @override
  DemoType get type => DemoType.game;
  @override
  Widget buildPage(BuildContext context) => const TetrisLuaPage();
}

void registerTetrisLuaDemo() => demoRegistry.register(TetrisLuaDemo());

// ══════════════════════════════════════════════════════════════
// 主页面
// ══════════════════════════════════════════════════════════════

class TetrisLuaPage extends StatefulWidget {
  const TetrisLuaPage({super.key});
  @override
  State<TetrisLuaPage> createState() => _TetrisLuaPageState();
}

class _TetrisLuaPageState extends State<TetrisLuaPage> {
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
      spec: kTetrisLobbySpec,
      slots: const GameLobbySlots(),
      onStarted: _onStarted,
    );
  }
}