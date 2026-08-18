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

import 'package:flutter/material.dart';
import '../lab_container.dart';
import 'package:xiaodouzi_fr/core/surround_game/board_theme.dart';
import 'tetris_lua/engine.dart' show RoomHandle;
import 'tetris_lua/widgets.dart' show LobbyEntryPage, OnlineGamePage;

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
      // 进入房间后，外层不再重复 AppBar，由 OnlineGamePage 内部 Scaffold 唯一提供返回按钮 + 标题
      return Scaffold(
        backgroundColor: bg,
        body: OnlineGamePage(handle: _handle!, onLeave: _disconnect),
      );
    }
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('俄罗斯方块'),
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
              child: Container(
                decoration: BoxDecoration(
                  color: theme.panelBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: theme.panelBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 表单（页面标题由 AppBar 唯一承载，避免卡片再渲染"俄罗斯方块"重复）
                    LobbyEntryPage(onJoined: _onJoined),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
