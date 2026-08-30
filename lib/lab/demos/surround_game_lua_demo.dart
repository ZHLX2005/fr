// lib/lab/demos/surround_game_lua_demo.dart
// 围追堵截（Quoridor）互联网双人对战 — v3 Lua 状态机版
//
// 流程（按 versus-game-room-template 标准）：
//   玩家输入昵称 + 房间码 → 点击"进入对局"
//   → tryJoinOrCreate：先 join；不存在则用此号创建
//   → snapshot.host_id == 我 ⇒ 我是 host（top）
//   → 双方 ACK × 2 → state="ready" → host DEAL → playing
//
// 镜像策略：
//   - 服务端存规范坐标（top = y0, bottom = y8）
//   - host 端 y 方向翻转后渲染（host 自身在下方）
//   - guest 端直接渲染
//   - 触摸坐标也相应翻转（保留 role-aware-board-mirror 特化逻辑）

import 'package:flutter/material.dart';
import '../lab_container.dart';
import 'package:xiaodouzi_fr/core/surround_game/board_theme.dart';
import 'surround_game_lua/engine.dart' show RoomHandle;
import 'surround_game_lua/widgets.dart' show LobbyEntryPage, OnlineGamePage;

// ══════════════════════════════════════════════════════════════
// Demo 注册
// ══════════════════════════════════════════════════════════════

class SurroundGameLuaDemo extends DemoPage {
  SurroundGameLuaDemo();
  @override String get title => '围追堵截（联机）';
  @override String get slug => 'surround-game-lua';
  @override String get description => 'Quoridor 互联网双人对战 · Lua 服务端权威棋谱';
  @override bool get preferFullScreen => true;
  // 归属游戏中心（联机 · 棋游），不再出现在 Lab 列表
  @override DemoType get type => DemoType.game;
  @override Widget buildPage(BuildContext context) => const SurroundGameLuaPage();
}

void registerSurroundGameLuaDemo() => demoRegistry.register(SurroundGameLuaDemo());

// ══════════════════════════════════════════════════════════════
// 主页面
// ══════════════════════════════════════════════════════════════

class SurroundGameLuaPage extends StatefulWidget {
  const SurroundGameLuaPage({super.key});
  @override State<SurroundGameLuaPage> createState() => _SurroundGameLuaPageState();
}

class _SurroundGameLuaPageState extends State<SurroundGameLuaPage> {
  RoomHandle? _handle;
  bool _isHostSide = false;

  @override
  void dispose() { _handle?.dispose(); super.dispose(); }
  void _onJoined(RoomHandle h, bool isHostSide) =>
      setState(() { _handle = h; _isHostSide = isHostSide; });
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
        body: OnlineGamePage(
          handle: _handle!, isHostSide: _isHostSide, onLeave: _disconnect,
        ),
      );
    }
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('围追堵截（联机）'),
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
                  // ── 主卡片 ──
                  Container(
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
                        // 表单（页面标题由 AppBar 唯一承载，避免卡片再渲染"围追堵截"重复）
                        LobbyEntryPage(onJoined: _onJoined),
                      ],
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
