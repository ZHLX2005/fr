// lib/core/game_kit/lobby/game_lobby_identity.dart
//
// 身份解析器抽象 —— GameLobbyPage 统一通过此接口取 device_id，
// 各游戏在 spec 里注入具体实现：
//   · chess → ChessIdentityResolver（chess 包内部实现）
//   · 其余 8 个 Lua 游戏 → RelayDeviceIdResolver（默认）
//
// 不在 game_kit 直接依赖 chess —— 避免循环。

import '../../../core/net_engine/relay_v3/relay_device_id.dart';

/// 抽象：返回稳定的 device_id（用于建房/加入房间时传给 transport）。
///
/// 不同游戏对此有不同语义（详见各自实现注释）：
///   - 纯设备 UUID：跨启动稳定，不感知登录身份
///   - 登录 uid 优先：登录后稳定为 uid，未登录回退设备 UUID
abstract class GameIdentityResolver {
  Future<String> resolve();
}

/// 默认实现：跨启动稳定的设备级 UUID（适用于无登录态语义的房间游戏）。
class RelayDeviceIdResolver implements GameIdentityResolver {
  const RelayDeviceIdResolver();

  @override
  Future<String> resolve() => RelayDeviceId.get();
}