// lib/core/draughts/lobby/draughts_lobby_spec.dart
//
// 国际跳棋的 GameLobbySpec —— smartMatch 单按钮入口。
//
// 与 chess 对齐：
//   · 规则（执子色 / 残局）在准备阶段由房主 SET_RULES，不在进房前配
//   · kDraughtsScript 经 assembleLuaScript 组装 → spec 为 final（非 const）
//   · AccountIdentityResolver（登录 uid 优先，未登录回退设备 UUID）——
//     换设备 / 重装 / 重登后重进同一房间号可恢复原座位，而非被误判「已满员」
//
// 与 gomoku/jungle 对齐：
//   · hintPosition = bottom；主按钮「进入对局」

import 'package:flutter/material.dart';

import '../../game_kit/lobby/game_lobby_identity.dart';
import '../../game_kit/lobby/game_lobby_spec.dart';
import '../p2p/script/draughts_script.dart';

/// 国际跳棋 relay 地址（与 chess / gomoku 同机）。
const String kDraughtsRelayUrl = 'http://47.110.80.47:8988';

/// 国际跳棋入口 spec（final — kDraughtsScript 经 assembleLuaScript 为 final）。
final GameLobbySpec kDraughtsLobbySpec = GameLobbySpec(
  gameId: 'draughts',
  title: '国际跳棋（联机）',
  heroIcon: Icons.circle_outlined,
  heroTagline: '输入房间号，与朋友对弈',
  relayUrl: kDraughtsRelayUrl,
  script: kDraughtsScript,
  maxPlayers: 2,
  flow: LobbyFlowType.smartMatch,
  identityResolver: const AccountIdentityResolver(),
  copy: const LobbyCopy(
    primaryBtnText: '进入对局',
    secondaryBtnText: null,
    hintIcon: '◐',
    hintPosition: HintPosition.bottom,
    hintText: '与朋友约定同一房间号：谁先进入谁是房主。白方先手（FMJD）。',
    aliasFieldHint: '昵称（如：白方）',
    codeFieldHint: '4–6 位大写字母数字',
  ),
);
