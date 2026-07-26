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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _EntryCard(
                        title: '进入对局',
                        subtitle: '输入昵称 + 房间号 · 第一个到的成为房主',
                        child: LobbyEntryPage(onJoined: _onJoined),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.center,
                        child: TextButton.icon(
                          onPressed: () =>
                              setState(() => _showOpeningStudy = true),
                          icon: const Icon(Icons.school_outlined, size: 18),
                          label: const Text('开局学习'),
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

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = BoardTheme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.panelBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: theme.panelBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: TextStyle(
                    color: theme.btnText,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: TextStyle(color: theme.btnSub, fontSize: 13)),
            child,
          ],
        ),
      ),
    );
  }
}