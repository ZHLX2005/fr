// lib/lab/demos/sudoku_lua/sudoku_demo.dart
// 数独（Sudoku）互联网双人对战 — v3 Lua 状态机版
//
// 流程（与 tetris 一致的 smartMatch 单入口）：
//   玩家输入昵称 + 房间号 → 点击「进入对局」（tryJoinOrCreate：
//   房间存在 → join；404 → 用此号建房；先到者 = 房主）
//   → SudokuRoomPage（lobby / ready / playing / ended 四态路由）
//
// 准备阶段由房主选难度并生成 puzzle（SudokuRoomConfigPanel 内嵌卡片），
// 双方 ready 后 host 点 START → 服务端切 'playing' → 棋盘出现 + 计时启动。
// 任一方填完点 SUBMIT → 服务端比对 solution → 全对者记录为 winner + 切 'ended'。

import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/lab/lab_container.dart';
import 'package:xiaodouzi_fr/core/game_kit/lobby/game_lobby_page.dart';
import 'package:xiaodouzi_fr/core/game_kit/lobby/game_lobby_slots.dart';
import 'package:xiaodouzi_fr/core/game_kit/lobby/game_lobby_spec.dart'
    show LobbyStartedCtx;
import 'package:xiaodouzi_fr/core/sudoku/sudoku.dart';

// ══════════════════════════════════════════════════════════════
// Demo 注册
// ══════════════════════════════════════════════════════════════

class SudokuLuaDemo extends DemoPage {
  SudokuLuaDemo();
  @override
  String get title => '数独（联机）';
  @override
  String get slug => 'sudoku-lua';
  @override
  String get description => 'Sudoku 互联网双人对战 · v3 Lua 服务端权威 · 同题竞速';
  @override
  bool get preferFullScreen => true;
  // 归属游戏中心（联机 · 益智），不出现在 Lab 列表
  @override
  DemoType get type => DemoType.game;
  @override
  Widget buildPage(BuildContext context) => const SudokuLuaPage();
}

void registerSudokuLuaDemo() => demoRegistry.register(SudokuLuaDemo());

// ══════════════════════════════════════════════════════════════
// 主页面
// ══════════════════════════════════════════════════════════════

class SudokuLuaPage extends StatefulWidget {
  const SudokuLuaPage({super.key});
  @override
  State<SudokuLuaPage> createState() => _SudokuLuaPageState();
}

class _SudokuLuaPageState extends State<SudokuLuaPage> {
  /// 大厅页 key：对弈页 pop 后调用 resetToEntry 回到入口表单。
  final GlobalKey<GameLobbyPageState> _lobbyKey =
      GlobalKey<GameLobbyPageState>();

  /// 对弈页句柄（dispose 时清理）。
  RoomHandle? _activeHandle;

  /// 进入对局：push SudokuRoomPage；pop 后 resetToEntry。
  Future<void> _onStarted(RoomHandle handle, LobbyStartedCtx ctx) async {
    _activeHandle = handle;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SudokuRoomPage(handle: handle),
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
      spec: kSudokuLobbySpec,
      slots: const GameLobbySlots(),
      onStarted: _onStarted,
    );
  }
}
