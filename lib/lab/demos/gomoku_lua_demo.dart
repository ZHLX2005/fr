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

import 'package:flutter/material.dart';
import '../lab_container.dart';
import 'package:xiaodouzi_fr/core/surround_game/board_theme.dart';
import 'gomoku_lua/engine.dart' show RoomHandle;
import 'gomoku_lua/widgets.dart' show LobbyEntryPage, OnlineGamePage;
import 'gomoku_lua/opening/gomoku_opening_player.dart';

// ══════════════════════════════════════════════════════════════
// Demo 注册
// ══════════════════════════════════════════════════════════════

class GomokuLuaDemo extends DemoPage {
  GomokuLuaDemo();
  @override String get title => '五子棋（Lua）';
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
  RoomHandle? _handle;
  bool _showOpeningStudy = false;

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
    // 用棋盘主题色（暖色），与游戏内色调一致
    final theme = BoardTheme.of(context);
    final bg = theme.boardSurface;
    final panelText = theme.btnText;
    if (_handle != null) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          title: const Text('五子棋'),
          backgroundColor: bg,
          foregroundColor: panelText,
          elevation: 0,
        ),
        body: OnlineGamePage(handle: _handle!, onLeave: _disconnect),
      );
    }
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('五子棋'),
        backgroundColor: bg,
        foregroundColor: panelText,
        elevation: 0,
      ),
      body: _showOpeningStudy
          ? GomokuOpeningPlayer(
              onBack: () => setState(() => _showOpeningStudy = false),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── 顶部无边框大字标题 ──
                      const Text(
                        '五子棋',
                        style: TextStyle(
                          color: Color(0xFF1F1B16),
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // 短分割线（不画完整边）
                      Container(
                        width: 32,
                        height: 2,
                        color: const Color(0xFF1F1B16),
                      ),
                      const SizedBox(height: 16),
                      // 单行 hint
                      Text(
                        '与朋友约定同一房间号，谁先到谁是房主',
                        style: TextStyle(
                          color: theme.btnSub,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 28),
                      // ── 表单区（无 Card） ──
                      LobbyEntryPage(onJoined: _onJoined),
                      const SizedBox(height: 24),
                      // ── 底部次要入口（纯文字链） ──
                      Align(
                        alignment: Alignment.center,
                        child: TextButton(
                          onPressed: () =>
                              setState(() => _showOpeningStudy = true),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            foregroundColor: theme.btnSub,
                          ),
                          child: const Text('开局学习',
                              style: TextStyle(fontSize: 13, letterSpacing: 1)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

// （_EntryCard 已废弃 —— 改为无边框布局后不再需要）