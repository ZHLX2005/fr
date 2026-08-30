// lib/lab/demos/coup_lua_demo.dart
// 政变（Coup）v3 Lua 状态机版 — 互联网多人对抗（2–6 人）
//
// 流程：
//   玩家输入昵称 + 房间码 → 点击"进入对局"
//   → tryJoinOrCreate：先 join；不存在则用此号创建
//   → 双方进入 → 房主点"开始游戏" → 服务端洗牌 + 发 2 张 + 给每人 2 金币
//   → 回合制：每回合选 7 个动作之一（INCOME/TAX/EXCHANGE/STEAL/ASSASSINATE/COUP/FOREIGN_AID）
//   → 其他玩家可质疑 / 通过 / 阻断（按 c.cur_phase 决定何时显示）
//   → 失去 2 张卡的玩家淘汰；最后存活者胜

import 'package:flutter/material.dart';
import '../lab_container.dart';
import 'package:xiaodouzi_fr/core/surround_game/board_theme.dart';
import 'coup_lua/engine.dart' show RoomHandle;
import 'coup_lua/widgets.dart' show LobbyEntryPage, OnlineGamePage;

// ══════════════════════════════════════════════════════════════
// Demo 注册
// ══════════════════════════════════════════════════════════════

class CoupLuaDemo extends DemoPage {
  CoupLuaDemo();
  @override
  String get title => '政变（联机）';
  @override
  String get slug => 'coup-lua';
  @override
  String get description => 'Coup 互联网多人对抗 · Lua 服务端权威 + 角色卡 + 质疑/阻断';
  @override
  bool get preferFullScreen => true;
  // 归属游戏中心（联机 · 派对），不出现在 Lab 列表
  @override
  DemoType get type => DemoType.game;
  @override
  Widget buildPage(BuildContext context) => const CoupLuaPage();
}

void registerCoupLuaDemo() => demoRegistry.register(CoupLuaDemo());

// ══════════════════════════════════════════════════════════════
// 主页面
// ══════════════════════════════════════════════════════════════

class CoupLuaPage extends StatefulWidget {
  const CoupLuaPage({super.key});
  @override
  State<CoupLuaPage> createState() => _CoupLuaPageState();
}

class _CoupLuaPageState extends State<CoupLuaPage> {
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
        title: const Text('政变（联机）'),
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
                    // 表单（页面标题由 AppBar 唯一承载，避免卡片再渲染"政变"重复）
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