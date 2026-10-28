// game/shell —— 联机对局页阶段分派壳（2026-10-28 自 3 个 lua demo 抽离）。
//
// 三个 lua 联机游戏（go / gomoku / surround_game）的对局页 build 各抄了一份
// 逐字相同的**阶段分派**：snapshot.state 为 lobby/ready（及 null）→ 准备页，
// ended → 终局页，其余 → 对局中。分派语义来自服务端快照状态机，与具体游戏
// 无关 —— 归位到这里后，「三阶段」只有一处真相。

import 'package:flutter/material.dart';

/// 对局页阶段分派：按 snapshot 状态在准备页 / 对局中 / 终局页之间切换。
class GamePhaseBody extends StatelessWidget {
  const GamePhaseBody({
    super.key,
    required this.phase,
    required this.lobby,
    required this.playing,
    required this.finished,
  });

  /// 服务端快照状态（snapshot.state）：null / lobby / ready / playing / ended。
  final String? phase;

  /// 准备页（lobby 与 ready 共用同一张卡片，只切换底部按钮区）。
  final WidgetBuilder lobby;

  /// 对局中。
  final WidgetBuilder playing;

  /// 终局页。
  final WidgetBuilder finished;

  @override
  Widget build(BuildContext context) {
    if (phase == null || phase == 'lobby' || phase == 'ready') {
      return lobby(context);
    }
    if (phase == 'ended') return finished(context);
    return playing(context);
  }
}
