// lib/core/localnet/http/http_endpoints.dart
//
// 通用 P2P HTTP 端点定义 — 所有游戏模块共用。

/// 端点路径常量
class HttpEndpoints {
  HttpEndpoints._();

  /// 获取对端信息（设备名、版本等）
  static const info = '/api/v1/info';

  /// 邀请对方
  static const invite = '/api/v1/invite';

  /// 接受邀请
  static const accept = '/api/v1/accept';

  /// 同步游戏状态
  static const gameState = '/api/v1/game-state';

  /// 发送聊天消息
  static const message = '/api/v1/message';
}

/// 默认 HTTP Server 端口
const int defaultHttpPort = 53318;
