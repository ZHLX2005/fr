/// 消息网络模式
///
/// - [lan]: 局域网 — UDP 多播发现 + HTTP P2P 通讯
/// - [relay]: 互联网 — 房间号发现 + WS 传输
enum MessageNetMode {
  lan,
  relay,
}
