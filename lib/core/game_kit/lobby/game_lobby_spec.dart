// lib/core/game_kit/lobby/game_lobby_spec.dart
//
// GameLobbySpec —— 入口页的纯数据配置。
//
// 每游戏一份 const（chess_lobby_spec.dart / gomoku_lobby_spec.dart / ...），
// 与 GameLobbySlots 一起驱动 GameLobbyPage 的 UI。
//
// 命名约束：
//   · gameId = slug 子串（与 kGameMeta 字符级一致）
//   · 不写死"chess"等具体游戏名 —— spec 自身不含游戏判断逻辑

import 'package:flutter/material.dart';

import 'game_lobby_identity.dart';

/// 入口流类型 —— 作为一等类型长期共存：
//   · smartMatch：单按钮「进入对局」，tryJoinOrCreate 成功后立即回调 onStarted
//                  （服务端 join 404 自动转 create），适合无建房配置的轻量游戏
//   · dualEntry：双按钮「创建房间」「加入房间」，创建路径 push 可选配置页
//                  再建房；snapshot 门控 onStarted（state ∈ {lobby,ready,playing,ended}），
//                  适合需要建房配置的复杂游戏（chess）
enum LobbyFlowType { smartMatch, dualEntry }

/// 提示行在表单里的位置。
enum HintPosition { top, bottom }

/// LobbyCopy —— 文案包。
///
/// 涵盖每游戏入口的「字段 hint / 按钮字 / 提示 icon / 提示行位置 / 房间号规则」差异。
/// 全部为字符串/枚举，**不写死具体游戏名**。
class LobbyCopy {
  /// 主按钮文字（smartMatch='「进入对局」'； dualEntry='「创建房间」'）
  final String primaryBtnText;

  /// 次按钮文字（dualEntry='「加入房间」'；smartMatch 留 null）
  final String? secondaryBtnText;

  /// 提示行 icon（◐ / ♛ 等 unicode 字符）
  final String hintIcon;

  /// 提示行位置
  final HintPosition hintPosition;

  /// 主提示文案（'与朋友约定同一房间号...'）
  final String hintText;

  /// 昵称字段 hint（'昵称（如：黑方）'）
  final String aliasFieldHint;

  /// 房间号字段 hint（'4–6 位大写字母数字'）
  final String codeFieldHint;

  /// 默认昵称（team_card: '玩家'；null = 强制必填）
  final String? defaultAlias;

  /// 是否启用随机房间号按钮（team_card 启用；其他游戏关闭）
  final bool randomCodeEnabled;

  /// 随机房间号按钮 tooltip
  final String? randomCodeHint;

  const LobbyCopy({
    required this.primaryBtnText,
    required this.secondaryBtnText,
    required this.hintIcon,
    required this.hintPosition,
    required this.hintText,
    required this.aliasFieldHint,
    required this.codeFieldHint,
    this.defaultAlias,
    this.randomCodeEnabled = false,
    this.randomCodeHint,
  });
}

/// GameLobbySpec —— 入口页数据配置。每游戏 const 一份。
///
/// 颜色由 GameLobbyPage 内部统一走 Theme.of(context).colorScheme + context.colors，
/// 不再在 spec 里声明颜色通道（消灭「入口页主题不一致」问题）。
class GameLobbySpec {
  /// 游戏 id（'chess' / 'gomoku' / ...）—— 命名/缓存目录派生 key
  final String gameId;

  /// 标题（'国际象棋（联机）'）
  final String title;

  /// 顶部大图标
  final IconData heroIcon;

  /// 副标题（'输入房间号，与朋友对弈'）
  final String heroTagline;

  /// Relay 服务地址
  final String relayUrl;

  /// Lua 脚本（kChessScript / kGomokuScript / ...）
  final String script;

  /// 最大玩家数
  final int maxPlayers;

  /// 入口流类型
  final LobbyFlowType flow;

  /// 文案包
  final LobbyCopy copy;

  /// 身份解析器
  final GameIdentityResolver identityResolver;

  /// 房间号最大长度（默认 6）
  final int maxCodeLength;

  /// 房间号最小长度（默认 4）
  final int minCodeLength;

  /// 是否在成功建房/加入后启用「断开」按钮（dualEntry 默认 true）
  final bool showDisconnectButton;

  const GameLobbySpec({
    required this.gameId,
    required this.title,
    required this.heroIcon,
    required this.heroTagline,
    required this.relayUrl,
    required this.script,
    required this.maxPlayers,
    required this.flow,
    required this.copy,
    required this.identityResolver,
    this.maxCodeLength = 6,
    this.minCodeLength = 4,
    this.showDisconnectButton = false,
  });
}

/// LobbySubmitData —— 进入「创建房间」配置页时透传的上下文。
///
/// 用于 chess 的 ChessRoomConfigPage 取 alias + code。
class LobbySubmitData {
  final String alias;
  final String code;

  const LobbySubmitData({required this.alias, required this.code});
}

/// LobbyStartedCtx —— onStarted 回调携带的额外上下文。
///
/// chess 之外的差异（如 surround 的 isHostSide、team_card 的「需要 host 配置」）
/// 通过 [GameLobbySlots.onStartedExtras] 注入扩展，避免污染基类。
class LobbyStartedCtx {
  final bool? isHostSide;

  /// 由 slots 写入的任意附加字段（如 isHostNeedsConfig）
  final Map<String, dynamic> extras;

  const LobbyStartedCtx({
    this.isHostSide,
    this.extras = const {},
  });
}

/// RoomCodeRules —— 房间号校验（共享默认实现，游戏可覆盖）。
///
/// 默认排除 0/O/1/I/L 易混字符（与 chess 原 LobbyEntryPage 行为一致）。
class RoomCodeRules {
  static const String kConfusingChars = '0O1IL';

  /// 返回 null 表示合法，否则返回错误信息。
  static String? validate(
    String code, {
    int minLen = 4,
    int maxLen = 6,
  }) {
    if (code.length < minLen || code.length > maxLen) {
      return '房间号为 $minLen–$maxLen 位大写字母数字';
    }
    if (code.contains(RegExp('[$kConfusingChars]'))) {
      return '房间号不能包含 0/O/1/I/L（易混淆）';
    }
    return null;
  }
}