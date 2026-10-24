// lib/lab/demos/xiangqi_lua_demo.dart
//
// 中国象棋（Xiangqi 9×10）互联网双人对战 — v3 Lua 状态机版。
//
// 流程（smartMatch 单入口）：
//   输入昵称 + 房间号 →「进入对局」（tryJoinOrCreate：先到 = 房主）
//   → XiangqiRoomPage：双方 ACK → host DEAL → 走子 / 吃子 / 将军
//   → 终局由客户端引擎判定后 CLAIM_END；host 可 RESET 再来一局
//
// 棋盘与棋子：
//   · 棋盘 = CustomPaint 画棋盘线 + 九宫 + 楚河汉界（交点式布局）
//   · 棋子 = 纯 SVG（圆盘 + 内环 + 汉字矢量 path），见 core/xiangqi/widgets/
//
// 对局功能：聊天（文字 + 表情）/ 认输 / 悔棋 / 求和。
// 不做本地 / AI；皮肤本期不做（棋盘配色走主题）。

import 'package:flutter/material.dart';

import '../lab_container.dart';
import '../../core/ui/game/game_lobby_page.dart';
import '../../core/game_kit/lobby/game_lobby_slots.dart';
import '../../core/game_kit/lobby/game_lobby_spec.dart' show LobbyStartedCtx;
import '../../core/net_engine/relay_v3/relay_v3_transport.dart' show RoomHandle;
import '../../core/xiangqi/lobby/xiangqi_lobby_spec.dart';
import '../../core/xiangqi/p2p/xiangqi_room_page.dart';

// ══════════════════════════════════════════════════════════════
// Demo 注册
// ══════════════════════════════════════════════════════════════

class XiangqiLuaDemo extends DemoPage {
  XiangqiLuaDemo();

  @override
  String get title => '中国象棋（联机）';

  @override
  String get slug => 'xiangqi-lua';

  @override
  String get description =>
      'Xiangqi 9×10 · Lua 服务端权威棋谱 · SVG 手绘棋子 · 聊天/认输/悔棋/求和';

  @override
  bool get preferFullScreen => true;

  @override
  DemoType get type => DemoType.game;

  @override
  Widget buildPage(BuildContext context) => const XiangqiLuaPage();
}

void registerXiangqiLuaDemo() => demoRegistry.register(XiangqiLuaDemo());

// ══════════════════════════════════════════════════════════════
// 主页面
// ══════════════════════════════════════════════════════════════

class XiangqiLuaPage extends StatefulWidget {
  const XiangqiLuaPage({super.key});

  @override
  State<XiangqiLuaPage> createState() => _XiangqiLuaPageState();
}

class _XiangqiLuaPageState extends State<XiangqiLuaPage> {
  /// 大厅页 key：对弈页 pop 后调用 resetToEntry 回到入口表单。
  final GlobalKey<GameLobbyPageState> _lobbyKey =
      GlobalKey<GameLobbyPageState>();

  /// 对弈页句柄（dispose 时清理）。
  RoomHandle? _activeHandle;

  /// 进入对局：push XiangqiRoomPage；pop 后 resetToEntry。
  Future<void> _onStarted(RoomHandle handle, LobbyStartedCtx ctx) async {
    _activeHandle = handle;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => XiangqiRoomPage(
          handle: handle,
          onLeave: () async {
            await handle.leave();
          },
        ),
      ),
    );
    _activeHandle = null;
    if (!mounted) return;
    _lobbyKey.currentState?.exposed.resetToEntry();
  }

  @override
  void dispose() {
    _activeHandle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GameLobbyPage(
      key: _lobbyKey,
      spec: kXiangqiLobbySpec,
      slots: const GameLobbySlots(),
      onStarted: _onStarted,
    );
  }
}
