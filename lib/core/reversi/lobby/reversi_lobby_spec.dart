// lib/core/reversi/lobby/reversi_lobby_spec.dart
//
// 黑白翻转棋（Othello / Reversi）Lua 联机的 GameLobbySpec。
//
// smartMatch 单表单：昵称 + 房间号 → tryJoinOrCreate → 立即进入。
// 黑/白由服务端开局随机分配（服务端权威 black_player_id）。

import 'package:flutter/material.dart';

import '../../game_kit/lobby/game_lobby_identity.dart';
import '../../game_kit/lobby/game_lobby_slots.dart';
import '../../game_kit/lobby/game_lobby_spec.dart';
import '../../../lab/demos/reversi_lua/constants.dart';
import '../../../lab/demos/reversi_lua/engine.dart' show kReversiScript;

const GameLobbySpec kReversiLobbySpec = GameLobbySpec(
  gameId: 'reversi-lua',
  title: '黑白翻转棋（联机）',
  heroIcon: Icons.circle_outlined,
  heroTagline: '输入房间号，与朋友对弈',
  relayUrl: kReversiRelayUrl,
  script: kReversiScript,
  maxPlayers: 2,
  flow: LobbyFlowType.smartMatch,
  identityResolver: RelayDeviceIdResolver(),
  copy: LobbyCopy(
    primaryBtnText: '进入对局',
    secondaryBtnText: null,
    hintIcon: '◐',
    hintPosition: HintPosition.bottom,
    hintText: '输入同一号码即可对战，黑白由服务端开局随机分配',
    aliasFieldHint: '昵称（如：黑方）',
    codeFieldHint: '4–6 位大写字母数字',
  ),
);

/// 黑白翻转棋入口用默认 slots（无定制）。
const GameLobbySlots kReversiLobbySlots = GameLobbySlots();