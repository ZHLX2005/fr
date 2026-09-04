// lib/core/game_kit/lobby/game_lobby_slots.dart
//
// GameLobbySlots —— 可选插槽（opt-in）。
//
// 默认 GameLobbyPage 用 spec 就能跑（smartMatch 流程）；
// 需要高级形态的游戏（chess）才提供以下插槽：
//   · configPageBuilder  —— 「创建房间」前 push 配置页
//   · initialParamsBuilder —— 注入游戏专属 initialParams（host_color 等）
//   · actionsBuilder  —— AppBar 附加按钮（换肤）
//   · formExtras  —— 房间号之后插入的额外 widget（残局 chip / 随机号按钮）
//   · transportBuilder —— 测试注入 transport
//   · onStartedExtras  —— 补充 LobbyStartedCtx 字段
//   · trailingEntry  —— demo 卡片外次要入口
//   · resetToEntry  —— 暴露给外部的「回到 entry 表单」句柄

import 'package:flutter/material.dart';

import '../../../core/net_engine/relay_v3/relay_v3_transport.dart';
import 'game_lobby_spec.dart';

typedef LobbyConfigPageBuilder = Future<Map<String, dynamic>?> Function(
  BuildContext context, {
  required LobbySubmitData data,
});

typedef LobbyInitialParamsBuilder = Map<String, dynamic> Function(
  LobbySubmitData data,
  Map<String, dynamic>? configResult,
);

typedef LobbyFormExtrasBuilder = List<Widget> Function(BuildContext context);

typedef LobbyActionsBuilder = List<Widget> Function(BuildContext context);

typedef LobbyTransportBuilder = RelayV3Transport Function(
  String alias,
  String deviceId,
);

typedef LobbyTrailingEntryBuilder = Widget Function(BuildContext context);

/// onStartedExtras —— 补充 LobbyStartedCtx 字段（surround / team_card）。
///
/// handler 收到 [ctx] 与 [handle] 两份上下文：
///   · ctx —— 写入 ctx.extras['needsConfig'] 等任意键
///   · handle —— 读 handle.latest（snapshot）+ handle.transport.deviceId
///     做服务端权威判断（host / state / alias ...）。
typedef LobbyOnStartedExtrasBuilder = void Function(
  LobbyStartedCtx ctx,
  RoomHandle handle,
);

class GameLobbySlots {
  /// 「创建房间」前置配置页（chess 用：弹 ChessRoomConfigPage 拿 host_color 等）；
  /// 返回 null = 用户取消；返回 Map = 加入 initialParams。
  final LobbyConfigPageBuilder? configPageBuilder;

  /// 注入游戏专属 initialParams（chess: host_color / first_mover / initial_fen）。
  final LobbyInitialParamsBuilder? initialParamsBuilder;

  /// 房间号字段之后插入的额外控件（chess: 残局 chip；team_card: 随机号按钮）。
  final LobbyFormExtrasBuilder? formExtras;

  /// AppBar 附加 actions（chess: 换肤按钮）。
  final LobbyActionsBuilder? actionsBuilder;

  /// demo 卡片外的次要入口（cowrite: 「查看本地参考」）。
  final LobbyTrailingEntryBuilder? trailingEntry;

  /// 测试注入 transport 构造（默认 = 真实 RelayV3Transport）。
  final LobbyTransportBuilder? transportBuilder;

  /// 补充 LobbyStartedCtx 字段（surround: isHostSide）。
  final LobbyOnStartedExtrasBuilder? onStartedExtras;

  /// 外部「回到 entry」句柄（dualEntry 模式，outer 在对弈页 pop 时调用）。
  final LobbyResetToEntryCallback? onResetToEntry;

  const GameLobbySlots({
    this.configPageBuilder,
    this.initialParamsBuilder,
    this.formExtras,
    this.actionsBuilder,
    this.trailingEntry,
    this.transportBuilder,
    this.onStartedExtras,
    this.onResetToEntry,
  });
}

/// GameLobbyPageState 暴露给外部的「resetToEntry」句柄。
typedef LobbyResetToEntryCallback = void Function(Future<void> Function() reset);

/// Build 出来的入口页 + 暴露给外部的句柄。
class GameLobbyHandle {
  /// 已连接的 RoomHandle（dualEntry 模式下有效）。
  final RoomHandle? handle;

  /// 调用以回到 entry 表单（断开 + 重置 phase）。
  final Future<void> Function() resetToEntry;

  const GameLobbyHandle({this.handle, required this.resetToEntry});
}

/// onStarted 回调签名（两种 flow 共用）。
typedef LobbyOnStarted = void Function(
  RoomHandle handle,
  LobbyStartedCtx ctx,
);