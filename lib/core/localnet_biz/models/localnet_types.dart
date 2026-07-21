/// 消息网络模式
enum MessageNetMode {
  /// 局域网：UDP 多播发现 + HTTP P2P
  lan,

  /// 互联网：HTTP 控制面（房间号）+ WS 传输
  relay,
}
