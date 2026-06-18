/// 传输层配置
class TransportConfig {
  const TransportConfig({
    this.httpPort = 53317,
    this.multicastAddress = '239.255.255.255',
    this.multicastPort = 5678,
    this.enableHttp = true,
    this.enableUdp = true,
  });

  final int httpPort;
  final String multicastAddress;
  final int multicastPort;
  final bool enableHttp;
  final bool enableUdp;
}
