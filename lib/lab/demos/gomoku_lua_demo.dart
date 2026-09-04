// lib/lab/demos/gomoku_lua_demo.dart
// 五子棋（Gomoku）互联网双人对战 — v3 Lua 状态机版（无房主版本）
//
// 流程：
//   玩家输入昵称 + 房间码 → 点击"进入对局"
//   → 服务端 join 尝试：404 → 用此号创建新房间
//   → 双方均进入后 ACK × 2 → 自动进入 playing
//
// 与围追堵截的差异：
//   - 15x15 对称棋盘，落子在交点
//   - 无镜像翻转（对称棋盘）
//   - 无房主区分：先进入=黑方（先手），后进入=白方
//   - 房间号由玩家口口相传，撞号时给提示换号
//   - 胜负 = 连五，客户端本地判定后发 WIN
//
// 入口迁移：原 LobbyEntryPage（lib/lab/demos/gomoku_lua/widgets.dart）
//   → GameLobbyPage + kGomokuLobbySpec（lib/core/gomoku/lobby/gomoku_lobby_spec.dart）。
//   「开局学习」入口移到 AppBar actionsBuilder（与 chess 残局库一致位置）。

import 'package:flutter/material.dart';
import '../lab_container.dart';
import 'gomoku_lua/engine.dart' show RoomHandle;
import 'gomoku_lua/widgets.dart' show OnlineGamePage;
import 'gomoku_lua/opening/gomoku_opening_player.dart';
import '../../core/game_kit/lobby/game_lobby_page.dart';
import '../../core/game_kit/lobby/game_lobby_slots.dart';
import '../../core/game_kit/lobby/game_lobby_spec.dart' show LobbyStartedCtx;
import '../../core/gomoku/lobby/gomoku_lobby_spec.dart';

// ══════════════════════════════════════════════════════════════
// Demo 注册
// ══════════════════════════════════════════════════════════════

class GomokuLuaDemo extends DemoPage {
  GomokuLuaDemo();
  @override String get title => '五子棋（联机）';
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
  @override
  State<GomokuLuaPage> createState() => _GomokuLuaPageState();
}

class _GomokuLuaPageState extends State<GomokuLuaPage> {
  /// 大厅页 key：对弈页 pop 后调用 resetToEntry 回到入口表单。
  final GlobalKey<GameLobbyPageState> _lobbyKey =
      GlobalKey<GameLobbyPageState>();

  /// 「开局学习」开关（true → 替换为 GomokuOpeningPlayer 全屏页面）。
  bool _showOpeningStudy = false;

  /// 对弈页 → 大厅重置句柄（push 前快照，pop 后用 resetToEntry 回到表单）。
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
    // 「开局学习」全屏页（与入口互斥，与原版一致）。
    if (_showOpeningStudy) {
      return GomokuOpeningPlayer(
        onBack: () => setState(() => _showOpeningStudy = false),
      );
    }
    // 通用入口页（自带 Scaffold + AppBar + 表单）。
    // AppBar 加「开局学习」按钮（与原版卡片外的 TextButton 同语义）。
    return GameLobbyPage(
      key: _lobbyKey,
      spec: kGomokuLobbySpec,
      slots: GameLobbySlots(
        actionsBuilder: (context) => [
          IconButton(
            icon: const Icon(Icons.school_outlined),
            tooltip: '开局学习',
            onPressed: () => setState(() => _showOpeningStudy = true),
          ),
        ],
      ),
      onStarted: _onStarted,
    );
  }
}