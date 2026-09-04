// lib/core/tetris/lobby/tetris_lobby_spec.dart
//
// 俄罗斯方块 (Tetris) 的 GameLobbySpec —— smartMatch 单按钮入口。
//
// 替代原 `lib/lab/demos/tetris_lua/widgets.dart` 里的 LobbyEntryPage，
// 行为零变化：
//   · 提示行 HintPosition.bottom
//   · aliasFieldHint = "昵称（如：玩家 A）"（无角色区分，A/B 即可）
//   · 主按钮 = "进入对局"
//   · maxPlayers = 2

import 'package:flutter/material.dart';

import '../../game_kit/lobby/game_lobby_identity.dart';
import '../../game_kit/lobby/game_lobby_spec.dart';
import '../../../lab/demos/tetris_lua/constants.dart';
import '../../../lab/demos/tetris_lua/tetris_script.dart';

/// 俄罗斯方块入口 spec const。
const GameLobbySpec kTetrisLobbySpec = GameLobbySpec(
  gameId: 'tetris',
  title: '俄罗斯方块（联机）',
  heroIcon: Icons.grid_view_rounded,
  heroTagline: '输入房间号，与朋友对弈',
  relayUrl: kTetrisRelayUrl,
  script: kTetrisScript,
  maxPlayers: 2,
  flow: LobbyFlowType.smartMatch,
  identityResolver: RelayDeviceIdResolver(),
  copy: LobbyCopy(
    primaryBtnText: '进入对局',
    secondaryBtnText: null,
    hintIcon: '◐',
    hintPosition: HintPosition.bottom,
    hintText: '输入同一号码即可对战，谁先到谁是房主',
    aliasFieldHint: '昵称（如：玩家 A）',
    codeFieldHint: '4–6 位大写字母数字',
  ),
);