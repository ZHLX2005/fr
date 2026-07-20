import 'remote_endpoint.dart';

/// 发现服务抽象 — LAN / Relay 后端各自实现
///
/// DeviceManager 持有一个 DiscoveryService，通过 watch() 流获得端点列表变化，
/// 通过 endpoints() 取当前快照。
abstract interface class DiscoveryService {
  /// 启动发现（LAN：绑定 UDP socket；Relay：HTTP POST /discover 注册）
  Future<void> start();

  /// 停止发现（释放端口/取消订阅）
  Future<void> stop();

  /// 当前已发现端点快照（不可变列表）
  List<RemoteEndpoint> get endpoints;

  /// 端点列表变化流 — 每次有新端点加入/丢失/更新时触发
  Stream<List<RemoteEndpoint>> watch();

  /// 主动探测（如 Relay：HTTP POST /probe 触发服务端 push 最新列表）
  Future<void> probe();
}