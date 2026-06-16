// lib/core/surround_game/lan/protocol/lan_channels.dart
//
// LAN 房间与游戏状态同步所用的 channel 字符串集中处。
// 所有 channel 命名规范：`surround/<domain>/<action>`。
// 本轮不实现 roomLeave（YAGNI）— 断线依赖 UDP 心跳超时 + deviceLost 检测。

abstract class LanChannels {
  /// Host 广播：建了房间
  static const String roomAnnounce = 'surround/room/announce';

  /// Client → Host：请求加入
  static const String roomJoin = 'surround/room/join';

  /// 双向：游戏状态增量同步
  static const String gameState = 'surround/game/state';
}
