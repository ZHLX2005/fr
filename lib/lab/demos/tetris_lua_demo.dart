// lib/lab/demos/tetris_lua_demo.dart
// 俄罗斯方块（Tetris）互联网双人对战 — v3 Lua 状态机版
//
// 与五子棋/围追堵截（回合制）的本质差异：双方各自本地实时玩，
// 服务端只下发共享方块序列 + 广播双方堆积状态/分数。非回合制。
//
// 流程：
//   房主创建房间 → 玩家输入码加入 → 双方 ACK → 房主点开始 → playing
//   → 各自本地玩（共享序列），落定时 SYNC 自己的板/分给对方看
//   → 一方堆顶 game over 发 LOSE → ended

import 'package:flutter/material.dart';
import '../lab_container.dart';
import 'package:xiaodouzi_fr/core/surround_game/board_theme.dart';
import 'tetris_lua/engine.dart' show RoomHandle, kTetrisAccent;
import 'tetris_lua/widgets.dart' show OnlineGamePage;
import 'tetris_lua/tetris_forms.dart' show SetupPage, JoinPage;

// ══════════════════════════════════════════════════════════════
// Demo 注册
// ══════════════════════════════════════════════════════════════

class TetrisLuaDemo extends DemoPage {
  TetrisLuaDemo();
  @override
  String get title => '俄罗斯方块';
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
  RoomHandle? _handle;
  bool _isMaster = true;

  @override
  void dispose() {
    _handle?.dispose();
    super.dispose();
  }

  void _onCreated(RoomHandle h) => setState(() => _handle = h);
  void _onJoined(RoomHandle h) => setState(() => _handle = h);

  Future<void> _disconnect() async {
    final h = _handle;
    setState(() => _handle = null);
    if (h != null) await h.leave();
  }

  @override
  Widget build(BuildContext context) {
    // 进入房间后交给 OnlineGamePage 全权管理（各阶段自带 Scaffold），
    // playing 用深色沉浸、lobby/ready 暖色，不再套外层 AppBar 避免色系割裂。
    if (_handle != null) {
      return OnlineGamePage(handle: _handle!, onLeave: _disconnect);
    }
    final theme = BoardTheme.of(context);
    return Scaffold(
      backgroundColor: theme.boardSurface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    color: theme.btnText,
                    onPressed: () => Navigator.maybePop(context),
                  ),
                  Icon(Icons.grid_view_rounded, color: kTetrisAccent, size: 26),
                  const SizedBox(width: 8),
                  Text(
                    '俄罗斯方块',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: theme.btnText,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('建房')),
                  ButtonSegment(value: false, label: Text('加入')),
                ],
                selected: {_isMaster},
                onSelectionChanged: (s) => setState(() => _isMaster = s.first),
              ),
            ),
            Expanded(
              child: _isMaster
                  ? SetupPage(onCreated: _onCreated)
                  : JoinPage(onJoined: _onJoined),
            ),
          ],
        ),
      ),
    );
  }
}
