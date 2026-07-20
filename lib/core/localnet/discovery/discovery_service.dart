import 'dart:async';

import 'discovery_event.dart';
import 'discovery_peer.dart';

/// 发现服务抽象 — LAN/Relay 统一的发现接口
///
/// LAN 实现：UDP 多播心跳
/// Relay 实现：HTTP 房间 API + WS 通知
abstract class DiscoveryService {
  /// 启动发现服务
  Future<void> start();

  /// 停止发现服务
  Future<void> stop();

  /// 当前发现的 peer 列表
  List<DiscoveryPeer> get peers;

  /// 发现事件流（peer 变化、房间加入/离开等）
  Stream<DiscoveryEvent> get events;

  /// 创建房间（仅 Relay 模式有效）
  Future<String?> createRoom({String? alias});

  /// 通过房间号加入（仅 Relay 模式有效）
  Future<DiscoveryEvent?> joinRoom(String roomCode, {String? alias});

  /// 离开当前房间（仅 Relay 模式有效）
  Future<void> leaveRoom();
}
