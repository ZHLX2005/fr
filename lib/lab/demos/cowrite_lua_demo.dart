// lib/lab/demos/cowrite_lua_demo.dart
//
// Co-Write Notebook（双人协作笔记本）— v3 Lua 状态机版。
//
// 流程：
//   - 输入昵称 + 房间号 → 点击"进入协作"
//   - 服务端 join 尝试：404 → 用此号创建新房间
//   - 双方进入后直接 playing（不需要 ACK；不是游戏）
//   - 任一方编辑 → 全量同步内容
//   - 单方可"占用广播权" → 把自己视图首行行号广播给对方
//   - 对方开启"自动对齐" → 滚动位置跟随
//   - "保存参考"按钮 → SharedPreferences 存当前内容（按 roomCode 分 key）

import 'package:flutter/material.dart';
import '../lab_container.dart';
import 'package:xiaodouzi_fr/core/surround_game/board_theme.dart';
import 'cowrite_lua/cowrite_engine.dart' show RoomHandle;
import 'cowrite_lua/cowrite_widgets.dart' show LobbyEntryPage, OnlineCoWritePage;

// ══════════════════════════════════════════════════════════════
// Demo 注册
// ══════════════════════════════════════════════════════════════

class CoWriteLuaDemo extends DemoPage {
  CoWriteLuaDemo();
  @override
  String get title => '协作笔记（Lua）';

  @override
  String get slug => 'cowrite-lua';

  @override
  String get description => '双人协作笔记本 · Lua 服务端权威 · 首行广播 + 自动对齐视图';

  @override
  bool get preferFullScreen => true;

  @override
  DemoType get type => DemoType.tool;

  @override
  Widget buildPage(BuildContext context) => const CoWriteLuaPage();
}

void registerCoWriteLuaDemo() => demoRegistry.register(CoWriteLuaDemo());

// ══════════════════════════════════════════════════════════════
// 主页面
// ══════════════════════════════════════════════════════════════

class CoWriteLuaPage extends StatefulWidget {
  const CoWriteLuaPage({super.key});

  @override
  State<CoWriteLuaPage> createState() => _CoWriteLuaPageState();
}

class _CoWriteLuaPageState extends State<CoWriteLuaPage> {
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
        body: OnlineCoWritePage(handle: _handle!, onLeave: _disconnect),
      );
    }
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('协作笔记'),
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
