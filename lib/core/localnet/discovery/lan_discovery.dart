import 'dart:async';
import 'dart:convert';

import 'package:xiaodouzi_fr/core/localnet/transport/transport_kind.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/udp_transport.dart';

import 'discovery_service.dart';
import 'remote_endpoint.dart';

/// LAN 发现服务 — 监听 UDP 多播心跳包
///
/// 解析 UdpTransport.datagrams 流中的 "deviceId,port,alias:xxx" 格式，
/// 转换为 RemoteEndpoint。DeviceManager 之前直接耦合 UDP 解析逻辑，
/// 本类将其隔离，RelayDiscovery 用类似接口注入即可。
class LanDiscovery implements DiscoveryService {
  LanDiscovery({
    required this.myDeviceId,
    required this.myAlias,
    required UdpTransport udp,
  }) : _udp = udp;

  final String myDeviceId;
  final String myAlias;
  final UdpTransport _udp;
  final Map<String, RemoteEndpoint> _endpoints = {};
  final StreamController<List<RemoteEndpoint>> _ctrl =
      StreamController<List<RemoteEndpoint>>.broadcast();
  StreamSubscription? _sub;
  bool _started = false;

  @override
  Future<void> start() async {
    if (_started) return;
    _sub = _udp.datagrams.listen(_onDatagram);
    _started = true;
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _endpoints.clear();
    _started = false;
  }

  @override
  List<RemoteEndpoint> get endpoints => List.unmodifiable(_endpoints.values);

  @override
  Stream<List<RemoteEndpoint>> watch() => _ctrl.stream;

  @override
  Future<void> probe() async {
    _ctrl.add(endpoints);
  }

  void _onDatagram(dynamic dg) {
    final data = dg.data as List<int>;
    final sender = dg.senderAddress;
    final text = utf8.decode(data, allowMalformed: true);
    if (!text.contains(',')) return;

    final parts = text.split(',');
    if (parts.length < 2) return;
    final id = parts[0].trim();
    final portStr = parts[1].trim();
    final port = int.tryParse(portStr);
    if (id.isEmpty || port == null) return;
    if (id == myDeviceId) return; // 忽略自己

    String alias = sender.address.toString();
    for (var i = 2; i < parts.length; i++) {
      final kv = parts[i].split(':');
      if (kv.length == 2 && kv[0].trim() == 'alias') {
        alias = kv[1].trim();
        break;
      }
    }

    final ep = RemoteEndpoint(
      deviceId: id,
      alias: alias,
      address: '${sender.address}:$port',
      kind: TransportKind.lan,
      lastSeen: DateTime.now(),
    );
    _endpoints[id] = ep;
    _ctrl.add(endpoints);
  }
}