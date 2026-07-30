// lib/lab/demos/reversi_demo.dart
//
// 黑白翻转棋（Othello / Reversi）Lua 版 demo 入口。
//
// 流程：
//   玩家输入昵称 + 房间码 → 点击"进入对局"
//   → 服务端 join 尝试：404 → 用此号创建新房间
//   → 双方均进入后 ACK × 2 → 房主点开始 → 服务端随机分配 black_player_id
//   → 进入 playing，轮流落子，悔棋 / 认输 / 终局 overlay
//
// 老的 core/reversi/pages/reversi_page.dart 是本地双人对战版本；
// 本 demo 走 Lua 服务端权威棋谱，重新写。

import 'package:flutter/material.dart';
import '../lab_container.dart';
import 'package:xiaodouzi_fr/core/surround_game/board_theme.dart';
import 'reversi_lua/engine.dart' show RoomHandle;
import 'reversi_lua/widgets.dart' show LobbyEntryPage, OnlineGamePage;

class ReversiLuaDemo extends DemoPage {
  ReversiLuaDemo();
  @override
  String get title => '黑白翻转棋（双人）';
  @override
  String get slug => 'reversi-lua';
  @override
  String get description => '棋游+联机 · Othello 互联网双人对战 · Lua 服务端权威棋谱';
  @override
  bool get preferFullScreen => true;
  // 归属游戏中心（联机 · 棋游）
  @override
  DemoType get type => DemoType.game;
  @override
  Widget buildPage(BuildContext context) => const ReversiLuaPage();
}

void registerReversiLuaDemo() => demoRegistry.register(ReversiLuaDemo());

class ReversiLuaPage extends StatefulWidget {
  const ReversiLuaPage({super.key});
  @override
  State<ReversiLuaPage> createState() => _ReversiLuaPageState();
}

class _ReversiLuaPageState extends State<ReversiLuaPage> {
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
    if (_handle != null) {
      // 进入房间后由 OnlineGamePage 内部 Scaffold 自管 AppBar（避免重复标题）
      return Scaffold(
        backgroundColor: bg,
        body: OnlineGamePage(handle: _handle!, onLeave: _disconnect),
      );
    }
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('黑白翻转棋'),
        backgroundColor: bg,
        foregroundColor: theme.btnText,
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
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 表单（页面标题由 AppBar 唯一承载，避免卡片再渲染"黑白翻转棋"重复）
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

// 旧入口（不再注册到 demoRegistry，仅保留 demo class 与 register 函数以兼容）
class ReversiDemo extends DemoPage {
  @override
  String get title => '黑白翻转棋（旧）';
  @override
  String get slug => 'reversi';
  @override
  String get description => '经典 Othello（已迁移到 Lua 版）';
  @override
  DemoType get type => DemoType.game;
  @override
  Widget buildPage(BuildContext context) => const _DeprecatedReversiStub();
}

void registerReversiDemo() {
  // 不再注册；保留函数签名以兼容历史调用点
}

class _DeprecatedReversiStub extends StatelessWidget {
  const _DeprecatedReversiStub();
  @override
  Widget build(BuildContext context) => const Center(
        child: Text('已迁移到 Lua 版：黑白翻转棋（Lua）',
            style: TextStyle(color: Colors.black54)),
      );
}