// lib/core/team_card/lobby/team_card_lobby_spec.dart
//
// team_card 的 GameLobbySpec —— 团建卡牌（联机）入口。
//
// 形态特殊点（相对其他 8 个 Lua 游戏）：
//   · 随机房间号按钮（copy.randomCodeEnabled = true）—— _lobby_form 内置实现
//   · 默认昵称 '玩家'（copy.defaultAlias）—— 兜底「不填昵称也能玩」
//   · 入房后由 snapshot 驱动房主配置页（state='setup' → 进 SetupPage）
//     通过 slots.onStartedExtras 注入 ctx.extras['needsConfig']，
//     demo 端 _onStarted 据此切换 phase 到 host_setup。
//
// 不复用 team_card 现有 widget 颜色通道（BoardTheme），由 _lobby_form
// 统一走 Theme.of(context).colorScheme + context.colors。
//
// 文件归属：spec 落 core/team_card/lobby（与 chess/gomoku 等同构），
// engine.dart / constants.dart / team_card_script.dart 仍位于
// lib/lab/demos/team_card/（不在迁移范围，不动）。

import 'package:flutter/material.dart';

import '../../../lab/demos/team_card/constants.dart' show kTeamCardRelayUrl;
import '../../../lab/demos/team_card/engine.dart' show kTeamCardScript;
import '../../game_kit/lobby/game_lobby_identity.dart';
import '../../game_kit/lobby/game_lobby_spec.dart';

/// team_card 入口 spec const。
///
/// flow = smartMatch：单按钮「进入对局」→ tryJoinOrCreate → 服务端权威判断
/// 我是房主（host）且 state=='setup' → demo 端 onStarted 切到 SetupPage 配置；
/// 房主 OPEN 后 waiting 玩家自动入座，state='lobby'，所有人进 PlayingView。
const GameLobbySpec kTeamCardLobbySpec = GameLobbySpec(
  gameId: 'team-card-lua',
  title: '团建卡牌（联机）',
  heroIcon: Icons.groups_outlined,
  heroTagline: '谁是卧底 / 狼人杀 · 输入房间号，与朋友开局',
  relayUrl: kTeamCardRelayUrl,
  script: kTeamCardScript,
  maxPlayers: 8,
  flow: LobbyFlowType.smartMatch,
  identityResolver: RelayDeviceIdResolver(),
  copy: LobbyCopy(
    primaryBtnText: '进入对局',
    secondaryBtnText: null,
    hintIcon: '◐',
    hintPosition: HintPosition.bottom,
    hintText: '输入同一号码即可开局，谁先到谁是房主；'
        '房主配置后其他人自动入座',
    aliasFieldHint: '昵称',
    codeFieldHint: '4–6 位大写字母数字',
    defaultAlias: '玩家',
    randomCodeEnabled: true,
    randomCodeHint: '随机生成房间号（我是房主）',
  ),
);
