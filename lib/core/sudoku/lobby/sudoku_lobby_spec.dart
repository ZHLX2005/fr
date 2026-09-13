// lib/core/sudoku/lobby/sudoku_lobby_spec.dart
//
// 数独联机竞赛的 GameLobbySpec —— smartMatch 单按钮入口。
//
// 与 tetris 一致的模式：单表单「昵称 + 房间号」→ tryJoinOrCreate →
// 立即进入。规则（难度）由 host 在准备阶段通过 SET_PUZZLE 推。

import 'package:flutter/material.dart';

import '../../game_kit/lobby/game_lobby_identity.dart';
import '../../game_kit/lobby/game_lobby_spec.dart';
import '../p2p/script/sudoku_script.dart';

/// 数独入口 spec（final，非 const — kSudokuScript 经 assembleLuaScript 组装为 final）。
final GameLobbySpec kSudokuLobbySpec = GameLobbySpec(
  gameId: 'sudoku',
  title: '数独竞赛（联机）',
  heroIcon: Icons.grid_4x4_rounded,
  heroTagline: '输入房间号，与朋友竞速解同一道题',
  relayUrl: 'http://47.110.80.47:8988',
  script: kSudokuScript,
  maxPlayers: 2,
  flow: LobbyFlowType.smartMatch,
  identityResolver: RelayDeviceIdResolver(),
  copy: LobbyCopy(
    primaryBtnText: '进入对局',
    secondaryBtnText: null,
    hintIcon: '◧',
    hintPosition: HintPosition.bottom,
    hintText: '输入同一号码即可对战，谁先到谁是房主。难度与题目由房主在准备阶段生成。',
    aliasFieldHint: '昵称（如：玩家 A）',
    codeFieldHint: '4–6 位大写字母数字',
  ),
);
