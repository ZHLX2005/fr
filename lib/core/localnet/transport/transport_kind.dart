/// 传输后端种类 — 决定 FrameworkCore 选 LanCore 还是 RelayCore
enum TransportKind {
  /// 局域网模式：UDP 多播发现 + HTTP P2P 传输
  lan,

  /// 互联网模式：HTTP 控制面（房间号注册/查询）+ WS 传输面
  relay,
}
