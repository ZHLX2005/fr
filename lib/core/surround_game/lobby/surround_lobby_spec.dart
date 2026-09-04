// lib/core/surround_game/lobby/surround_lobby_spec.dart
//
// 围追堵截（Quoridor）Lua 联机的 GameLobbySpec。
//
// smartMatch 单表单：昵称 + 房间号 → tryJoinOrCreate → 立即进入。
// isHostSide 由 demo 端在 onStarted 回调里读 snapshot.host_id 计算（不依赖 slots）。

import 'package:flutter/material.dart';

import '../../game_kit/lobby/game_lobby_identity.dart';
import '../../game_kit/lobby/game_lobby_slots.dart';
import '../../game_kit/lobby/game_lobby_spec.dart';
import '../../../lab/demos/surround_game_lua/constants.dart';
import '../../../lab/demos/surround_game_lua/engine.dart' show kSurroundGameScript;

const GameLobbySpec kSurroundLobbySpec = GameLobbySpec(
  gameId: 'surround-game-lua',
  title: '围追堵截（联机）',
  heroIcon: Icons.crop_square,
  heroTagline: '输入房间号，与朋友对弈',
  relayUrl: kSgRelayUrl,
  script: kSurroundGameScript,
  maxPlayers: 2,
  flow: LobbyFlowType.smartMatch,
  identityResolver: RelayDeviceIdResolver(),
  copy: LobbyCopy(
    primaryBtnText: '进入对局',
    secondaryBtnText: null,
    hintIcon: '◐',
    hintPosition: HintPosition.bottom,
    hintText: '输入同一号码即可对战，谁先到谁是房主',
    aliasFieldHint: '昵称（如：红方）',
    codeFieldHint: '4–6 位大写字母数字',
  ),
);

/// 围追堵截入口用默认 slots（无定制）。
const GameLobbySlots kSurroundLobbySlots = GameLobbySlots();