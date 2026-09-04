// lib/lab/demos/jungle_chess_lua_demo.dart
//
// 斗兽棋互联网双人对战 — v3 Lua 状态机版。
//
// 流程：
//   - 输入昵称 + 房间号 → 点击"进入对局"
//   - 服务端 join 尝试：404 → 用此号创建新房间
//   - 双方均进入后 ACK × 2 → 房主点"开始游戏"
//   - 走子 / 吃子 / 陷阱 / 河跳 → 服务端权威 history
//   - 胜负由客户端本地 JungleEngine 判定（进入对方兽穴 / 全灭 / 无子可走）后发 WIN
//   - 房主认输 / RESET 回到 lobby
//
// 关键特性（与五子棋对比）：
//   - **棋盘完全对称**：host 端（top）整体翻转，让双方都看到"自己在底部"。
//   - **大小写字母**：服务端 history 不存字母，但引擎暴露 `pieceLetter` 给棋谱/调试。
//   - **共享昵称**：LuaGameAlias（4 个 Lua 游戏共用）。
//
// 入口迁移：原 LobbyEntryPage（lib/lab/demos/jungle_chess_lua/widgets.dart）
//   → GameLobbyPage + kJungleLobbySpec（lib/core/jungle/lobby/jungle_lobby_spec.dart）。

import 'package:flutter/material.dart';
import '../lab_container.dart';
import 'jungle_chess_lua/jungle_engine.dart' show RoomHandle;
import 'jungle_chess_lua/widgets.dart' show OnlineGamePage;
import '../../core/game_kit/lobby/game_lobby_page.dart';
import '../../core/game_kit/lobby/game_lobby_slots.dart';
import '../../core/game_kit/lobby/game_lobby_spec.dart' show LobbyStartedCtx;
import '../../core/jungle/lobby/jungle_lobby_spec.dart';

// ══════════════════════════════════════════════════════════════
// Demo 注册
// ══════════════════════════════════════════════════════════════

class JungleChessLuaDemo extends DemoPage {
  JungleChessLuaDemo();
  @override
  String get title => '斗兽棋（联机）';

  @override
  String get slug => 'jungle-chess-lua';

  @override
  String get description => '斗兽棋互联网双人对战 · Lua 服务端权威棋谱 · 棋盘对称翻转';

  @override
  bool get preferFullScreen => true;

  @override
  DemoType get type => DemoType.game;

  @override
  Widget buildPage(BuildContext context) => const JungleChessLuaPage();
}

void registerJungleChessLuaDemo() => demoRegistry.register(JungleChessLuaDemo());

// ══════════════════════════════════════════════════════════════
// 主页面
// ══════════════════════════════════════════════════════════════

class JungleChessLuaPage extends StatefulWidget {
  const JungleChessLuaPage({super.key});

  @override
  State<JungleChessLuaPage> createState() => _JungleChessLuaPageState();
}

class _JungleChessLuaPageState extends State<JungleChessLuaPage> {
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
      spec: kJungleLobbySpec,
      slots: const GameLobbySlots(),
      onStarted: _onStarted,
    );
  }
}