// lib/core/chess/lobby/chess_lobby_spec.dart
//
// chess 的 GameLobbySpec + GameLobbySlots 实例。
//
// 入口流（v7）：
//   · smartMatch 单入口「进入对局」→ tryJoinOrCreate（先到 = 房主）
//   · 房间规则（host_color / first_mover / 残局）在准备阶段由房主配置
//     （ChessRoomPage lobby/ready + Lua SET_RULES），不在进房前配
//   · ChessIdentity（登录 uid 优先）身份通道
//   · AppBar 换肤按钮（actionsBuilder 插槽）；残局库改到准备卡内
//
// chess 的脚本经 LuaScriptAssembler 组装（lifecycle + actions + emoji），
// 因此为 final（非 const）—— assembleLuaScript 在 runtime 做字符串拼接。

import 'package:flutter/material.dart';

import '../../game_kit/lobby/game_lobby_identity.dart';
import '../../game_kit/lobby/game_lobby_slots.dart';
import '../../game_kit/lobby/game_lobby_spec.dart';
import '../p2p/chess_identity.dart';
import '../p2p/script/chess_script.dart';

/// chess 专属 IdentityResolver —— 包装 ChessIdentity.resolve()（登录 uid 优先）。
class _ChessIdentityResolver implements GameIdentityResolver {
  const _ChessIdentityResolver();

  @override
  Future<String> resolve() => ChessIdentity.resolve();
}

/// chess 入口 spec（final，非 const — kChessScript 经 assembleLuaScript 组装为 final）。
final GameLobbySpec kChessLobbySpec = GameLobbySpec(
  gameId: 'chess',
  title: '国际象棋（联机）',
  heroIcon: Icons.meeting_room_outlined,
  heroTagline: '输入房间号，与朋友对弈',
  relayUrl: 'http://47.110.80.47:8988',
  script: kChessScript,
  maxPlayers: 2,
  flow: LobbyFlowType.smartMatch,
  identityResolver: _ChessIdentityResolver(),
  copy: const LobbyCopy(
    primaryBtnText: '进入对局',
    secondaryBtnText: null,
    hintIcon: '◐',
    hintPosition: HintPosition.bottom,
    hintText: '与朋友约定同一房间号：谁先进入谁是房主，后到者为对手。规则由房主在准备阶段配置。',
    aliasFieldHint: '如：小白',
    codeFieldHint: '4–6 位大写字母数字',
  ),
);

/// 构造 chess 用的 GameLobbySlots。
///
/// 规则配置已移入 [ChessRoomPage] 准备阶段；此处仅挂 AppBar actions（换肤等）。
GameLobbySlots buildChessLobbySlots({
  required LobbyActionsBuilder actionsBuilder,
}) {
  return GameLobbySlots(
    actionsBuilder: actionsBuilder,
  );
}
