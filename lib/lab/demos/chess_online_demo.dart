// lib/lab/demos/chess_online_demo.dart
// 国际象棋（Chess）互联网双人对战 — v3 Lua 状态机版
//
// 流程（RelayV3Lobby 标准流程）：
//   玩家输入昵称 → 创建房间（host = 白方）或加入房间（guest = 黑方）
//   → lobby 等待 → 房主点"开始游戏" → state == "playing"
//   → onStarted 回调把 RoomHandle 交给 ChessRoomPage（业务层接管）
//
// 棋盘 / 皮肤 / 走法引擎全部复用 lib/core/chess/ 模块；
// 本 demo 只负责"大厅 → 房间页"的入口路由。

import 'package:flutter/material.dart';
import '../lab_container.dart';
import '../../core/net_engine/relay_v3/relay_v3_widget.dart';
import '../../core/net_engine/relay_v3/relay_v3_transport.dart' show RoomHandle;
import '../../core/chess/p2p/chess_script.dart';
import '../../core/chess/p2p/chess_room_page.dart';

// ══════════════════════════════════════════════════════════════
// Demo 注册
// ══════════════════════════════════════════════════════════════

class ChessOnlineDemo extends DemoPage {
  ChessOnlineDemo();
  @override String get title => '国际象棋在线';
  @override String get slug => 'chess-online';
  @override String get description => 'Chess 互联网双人对战 · v3 Lua 服务端权威';
  @override bool get preferFullScreen => true;
  // 归属游戏中心（联机 · 棋游），不再出现在 Lab 列表
  @override DemoType get type => DemoType.game;
  @override Widget buildPage(BuildContext context) => const ChessOnlinePage();
}

void registerChessOnlineDemo() => demoRegistry.register(ChessOnlineDemo());

// ══════════════════════════════════════════════════════════════
// 主页面
// ══════════════════════════════════════════════════════════════

class ChessOnlinePage extends StatefulWidget {
  const ChessOnlinePage({super.key});
  @override
  State<ChessOnlinePage> createState() => _ChessOnlinePageState();
}

class _ChessOnlinePageState extends State<ChessOnlinePage> {
  /// Relay v3 大厅 → state=="playing" 时触发，把房间句柄交给对弈房间页。
  void _onStarted(RoomHandle handle) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChessRoomPage(handle: handle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // RelayV3Lobby 自带 Scaffold + AppBar（建房 / 加入 / 大厅 / 开始）。
    // 进入 playing 后 lobby 内部渲染 SizedBox.shrink（见 RelayV3Lobby.build），
    // 由 onStarted push 的 ChessRoomPage 接管界面。
    return RelayV3Lobby(
      relayUrl: 'http://47.110.80.47:8988',
      script: kChessScript,
      maxPlayers: 2,
      title: '国际象棋在线',
      onStarted: _onStarted,
    );
  }
}
