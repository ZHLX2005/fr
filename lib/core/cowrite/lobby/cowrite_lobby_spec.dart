// lib/core/cowrite/lobby/cowrite_lobby_spec.dart
//
// 协作笔记（Co-Write Notebook）Lua 联机的 GameLobbySpec。
//
// smartMatch 单表单：昵称 + 房间号 → tryJoinOrCreate → 立即进入。
// 不需要 ACK（不是游戏），双方进入即 playing。

import 'package:flutter/material.dart';

import '../../game_kit/lobby/game_lobby_identity.dart';
import '../../game_kit/lobby/game_lobby_slots.dart';
import '../../game_kit/lobby/game_lobby_spec.dart';
import '../../../lab/demos/cowrite_lua/cowrite_constants.dart';
import '../../../lab/demos/cowrite_lua/cowrite_engine.dart' show kCoWriteScript;

const GameLobbySpec kCoWriteLobbySpec = GameLobbySpec(
  gameId: 'cowrite-lua',
  title: '协作笔记（联机）',
  heroIcon: Icons.edit_note,
  heroTagline: '输入房间号，与朋友协作',
  relayUrl: kCoWriteRelayUrl,
  script: kCoWriteScript,
  maxPlayers: kCoWriteMaxPlayers,
  flow: LobbyFlowType.smartMatch,
  identityResolver: RelayDeviceIdResolver(),
  copy: LobbyCopy(
    primaryBtnText: '进入协作',
    secondaryBtnText: null,
    hintIcon: '◐',
    hintPosition: HintPosition.top,
    hintText: '同一房间号进入即可协作；可设置"我的首行广播"和"自动对齐"',
    aliasFieldHint: '昵称',
    codeFieldHint: '4–6 位大写字母数字',
  ),
);

/// 协作笔记入口用默认 slots（无定制；「查看本地参考」次要入口由 demo 自渲染）。
const GameLobbySlots kCoWriteLobbySlots = GameLobbySlots();