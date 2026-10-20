// lib/core/xiangqi/lobby/xiangqi_lobby_spec.dart
//
// 中国象棋的 GameLobbySpec —— smartMatch 单按钮入口。
//
// 与 chess / draughts 对齐：
//   · 规则（执子色 / 残局）在准备阶段由房主 SET_RULES，不在进房前配
//   · kXiangqiScript 经 assembleLuaScript 组装 → spec 为 final（非 const）
//   · AccountIdentityResolver（登录 uid 优先，未登录回退设备 UUID）——
//     换设备 / 重装 / 重登后重进同一房间号可恢复原座位，而非被误判「已满员」
//
// 与 gomoku / jungle / draughts 对齐：
//   · hintPosition = bottom；主按钮「进入对局」
//
// ## 中国象棋特有的文案
//
//   · 执子色是「红 / 黑」而不是「白 / 黑」；红先黑后。
//   · 昵称 hint 给「红方 / 黑方」两个示例。

import 'package:flutter/material.dart';

import '../../game_kit/lobby/game_lobby_identity.dart';
import '../../game_kit/lobby/game_lobby_spec.dart';
import '../p2p/script/xiangqi_script.dart';

/// 中国象棋 relay 地址（与 chess / draughts 同机）。
const String kXiangqiRelayUrl = 'http://47.110.80.47:8988';

/// 中国象棋入口 spec（final — kXiangqiScript 经 assembleLuaScript 为 final）。
final GameLobbySpec kXiangqiLobbySpec = GameLobbySpec(
  gameId: 'xiangqi',
  title: '中国象棋（联机）',
  heroIcon: Icons.grid_on_rounded,
  heroTagline: '输入房间号，与朋友对弈',
  relayUrl: kXiangqiRelayUrl,
  script: kXiangqiScript,
  maxPlayers: 2,
  flow: LobbyFlowType.smartMatch,
  identityResolver: const AccountIdentityResolver(),
  copy: const LobbyCopy(
    primaryBtnText: '进入对局',
    secondaryBtnText: null,
    hintIcon: '◐',
    hintPosition: HintPosition.bottom,
    hintText: '与朋友约定同一房间号：谁先进入谁是房主。红先黑后。',
    aliasFieldHint: '昵称（如：红方）',
    codeFieldHint: '4–6 位大写字母数字',
  ),
);
