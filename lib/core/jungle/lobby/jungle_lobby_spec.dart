// lib/core/jungle/lobby/jungle_lobby_spec.dart
//
// 斗兽棋 (Jungle Chess) 的 GameLobbySpec —— smartMatch 单按钮入口。
//
// 与五子棋/围棋的差异：
//   · hintPosition = HintPosition.top（红方/蓝方角色说明放表单顶部，
//     让玩家一眼看清自己要选哪个颜色对应昵称）
//   · aliasFieldHint = "昵称（如：红方 / 蓝方）"
//   · 主按钮 = "进入对局"
//   · maxPlayers = 2
//
// 替代原 `lib/lab/demos/jungle_chess_lua/widgets.dart` 里的 LobbyEntryPage。

import 'package:flutter/material.dart';

import '../../game_kit/lobby/game_lobby_identity.dart';
import '../../game_kit/lobby/game_lobby_spec.dart';
import '../../../lab/demos/jungle_chess_lua/jungle_constants.dart';
import '../../../lab/demos/jungle_chess_lua/jungle_lua_script.dart';

/// 斗兽棋入口 spec const。
const GameLobbySpec kJungleLobbySpec = GameLobbySpec(
  gameId: 'jungle',
  title: '斗兽棋（联机）',
  heroIcon: Icons.pets_rounded,
  heroTagline: '输入房间号，与朋友对弈',
  relayUrl: kJungleLuaRelayUrl,
  script: kJungleChessScript,
  maxPlayers: 2,
  flow: LobbyFlowType.smartMatch,
  identityResolver: RelayDeviceIdResolver(),
  copy: LobbyCopy(
    primaryBtnText: '进入对局',
    secondaryBtnText: null,
    hintIcon: '◐',
    hintPosition: HintPosition.top,
    hintText: '输入同一号码即可对战，红方（host）先手',
    aliasFieldHint: '昵称（如：红方 / 蓝方）',
    codeFieldHint: '4–6 位大写字母数字',
  ),
);