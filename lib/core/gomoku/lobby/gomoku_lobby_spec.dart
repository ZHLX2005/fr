// lib/core/gomoku/lobby/gomoku_lobby_spec.dart
//
// 五子棋 (Gomoku) 的 GameLobbySpec —— smartMatch 单按钮入口。
//
// 与 chess 范本差异：去掉 dualEntry 与身份通道，直接用 RelayDeviceIdResolver。
// 与 chess 范本相同：const 数据 + 零 slots（formExtras / actionsBuilder 都为空）。
//
// 替代原 `lib/lab/demos/gomoku_lua/widgets.dart` 里的 LobbyEntryPage，
// 行为零变化：
//   · 提示行 HintPosition.bottom（房主说明放表单下方）
//   · aliasFieldHint = "昵称（如：黑方）"（先手方习惯称呼）
//   · 主按钮 = "进入对局"
//   · maxPlayers = 2

import 'package:flutter/material.dart';

import '../../game_kit/lobby/game_lobby_identity.dart';
import '../../game_kit/lobby/game_lobby_spec.dart';
import '../../../lab/demos/gomoku_lua/constants.dart';
import '../../../lab/demos/gomoku_lua/gomoku_script.dart';

/// 五子棋入口 spec const。
const GameLobbySpec kGomokuLobbySpec = GameLobbySpec(
  gameId: 'gomoku',
  title: '五子棋（联机）',
  heroIcon: Icons.grid_4x4_rounded,
  heroTagline: '输入房间号，与朋友对弈',
  relayUrl: kGomokuRelayUrl,
  script: kGomokuScript,
  maxPlayers: 2,
  flow: LobbyFlowType.smartMatch,
  identityResolver: RelayDeviceIdResolver(),
  copy: LobbyCopy(
    primaryBtnText: '进入对局',
    secondaryBtnText: null,
    hintIcon: '◐',
    hintPosition: HintPosition.bottom,
    hintText: '输入同一号码即可对战，谁先到谁是房主',
    aliasFieldHint: '昵称（如：黑方）',
    codeFieldHint: '4–6 位大写字母数字',
  ),
);