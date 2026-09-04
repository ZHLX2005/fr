// lib/core/go/lobby/go_lobby_spec.dart
//
// 围棋 (Go) 的 GameLobbySpec —— smartMatch 单按钮入口。
//
// 替代原 `lib/lab/demos/go_lua/widgets.dart` 里的 LobbyEntryPage，
// 行为零变化：
//   · 提示行 HintPosition.bottom
//   · aliasFieldHint = "昵称（如：黑方）"（先手方习惯称呼）
//   · 主按钮 = "进入对局"
//   · maxPlayers = 2

import 'package:flutter/material.dart';

import '../../game_kit/lobby/game_lobby_identity.dart';
import '../../game_kit/lobby/game_lobby_spec.dart';
import '../../../lab/demos/go_lua/go_constants.dart';
import '../../../lab/demos/go_lua/go_script.dart';

/// 围棋入口 spec const。
const GameLobbySpec kGoLobbySpec = GameLobbySpec(
  gameId: 'go',
  title: '围棋（联机）',
  heroIcon: Icons.circle_outlined,
  heroTagline: '输入房间号，与朋友对弈',
  relayUrl: kGoRelayUrl,
  script: kGoScript,
  maxPlayers: 2,
  flow: LobbyFlowType.smartMatch,
  identityResolver: RelayDeviceIdResolver(),
  copy: LobbyCopy(
    primaryBtnText: '进入对局',
    secondaryBtnText: null,
    hintIcon: '◐',
    hintPosition: HintPosition.bottom,
    hintText: '输入同一号码即可对战，谁先到谁是黑方（先手）',
    aliasFieldHint: '昵称（如：黑方）',
    codeFieldHint: '4–6 位大写字母数字',
  ),
);