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

import 'package:flutter/material.dart';
import '../lab_container.dart';
import 'package:xiaodouzi_fr/core/surround_game/board_theme.dart';
import 'jungle_chess_lua/jungle_engine.dart' show RoomHandle;
import 'jungle_chess_lua/widgets.dart' show LobbyEntryPage, OnlineGamePage;

// ══════════════════════════════════════════════════════════════
// Demo 注册
// ══════════════════════════════════════════════════════════════

class JungleChessLuaDemo extends DemoPage {
  JungleChessLuaDemo();
  @override
  String get title => '斗兽棋（Lua）';

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
        title: const Text('斗兽棋（Lua）'),
        backgroundColor: bg,
        foregroundColor: panelText,
        elevation: 0,
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.panelBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: theme.panelBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.06),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [LobbyEntryPage(onJoined: _onJoined)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
