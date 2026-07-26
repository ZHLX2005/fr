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
          : SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
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
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Hero 标题
                          Text(
                            '五子棋',
                            style: TextStyle(
                              color: theme.btnText,
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(width: 24, height: 2, color: theme.btnText),
                          const SizedBox(height: 14),
                          // chip 副标题
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: theme.btnText.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '自动匹配对战',
                              style: TextStyle(
                                color: theme.btnText,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          // 表单
                          LobbyEntryPage(onJoined: _onJoined),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // ── 卡片外次要入口 ──
                    Center(
                      child: TextButton.icon(
                        onPressed: () =>
                            setState(() => _showOpeningStudy = true),
                        style: TextButton.styleFrom(
                          foregroundColor: theme.btnSub,
                        ),
                        icon: const Icon(Icons.school_outlined, size: 18),
                        label: const Text('开局学习',
                            style: TextStyle(letterSpacing: 1)),
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

// （_EntryCard 已废弃 —— 改为无边框布局后不再需要）