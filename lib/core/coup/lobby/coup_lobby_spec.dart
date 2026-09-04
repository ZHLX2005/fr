// lib/core/coup/lobby/coup_lobby_spec.dart
//
// 政变（Coup）Lua 联机的 GameLobbySpec —— 多达 6 人对抗。
//
// smartMatch 单表单：昵称 + 房间号 → tryJoinOrCreate → 立即进入。

import 'package:flutter/material.dart';

import '../../game_kit/lobby/game_lobby_identity.dart';
import '../../game_kit/lobby/game_lobby_slots.dart';
import '../../game_kit/lobby/game_lobby_spec.dart';
import '../../../lab/demos/coup_lua/constants.dart';
import '../../../lab/demos/coup_lua/engine.dart' show kCoupScript;

const GameLobbySpec kCoupLobbySpec = GameLobbySpec(
  gameId: 'coup-lua',
  title: '政变（联机）',
  heroIcon: Icons.local_fire_department_outlined,
  heroTagline: '输入房间号，多人对战',
  relayUrl: kCoupRelayUrl,
  script: kCoupScript,
  maxPlayers: 6,
  flow: LobbyFlowType.smartMatch,
  identityResolver: RelayDeviceIdResolver(),
  copy: LobbyCopy(
    primaryBtnText: '进入对局',
    secondaryBtnText: null,
    hintIcon: '♛',
    hintPosition: HintPosition.bottom,
    hintText: '2–6 人对局，输入同一房间号即加入；房主建房 + 开局',
    aliasFieldHint: '昵称',
    codeFieldHint: '4–6 位大写字母数字',
  ),
);

/// 政变入口用默认 slots（无定制）。
const GameLobbySlots kCoupLobbySlots = GameLobbySlots();