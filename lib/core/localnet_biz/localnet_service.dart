// lib/core/localnet_biz/localnet_service.dart
//
// LocalNet biz 服务 — v2 pub/sub 模式（不再依赖 DataLog/scope）

import 'dart:async';

import 'package:xiaodouzi_fr/core/localnet/localnet.dart' as fw;

import 'localnet_message.dart';

/// 房间事件（业务层订阅此流驱动 UI）
sealed class RoomEvent {}

class PeerJoined extends RoomEvent {
  final String deviceId;
  final String alias;
  PeerJoined(this.deviceId, this.alias);
}

class PeerLeft extends RoomEvent {
  final String deviceId;
  PeerLeft(this.deviceId);
}

class MessageReceived extends RoomEvent {
  final LocalnetMessage msg;
  MessageReceived(this.msg);
}

/// 业务层房间助手 — 封装 subscribe/publish 细节
///
/// 使用方式：
/// 1. master: createRoom(config) → 拿到 info
/// 2. player: joinRoom(code, alias)
/// 3. 两者都要 subscribeRoom(code) 监听事件
/// 4. sendMessage() 发消息
class LocalnetService {
  fw.RelayTransport? _transport;
  StreamSubscription<fw.RemoteEvent>? _sub;
  String? _roomCode;
  String? _myNodeId;

  final _eventsCtrl = StreamController<RoomEvent>.broadcast();
  Stream<RoomEvent> get events => _eventsCtrl.stream;

  String? get roomCode => _roomCode;
  String? get myNodeId => _myNodeId;

  /// 房主建房
  Future<fw.RoomInfo> createRoom({
    required String relayUrl,
    required String alias,
    int maxPlayers = 2,
    Map<String, dynamic> schema = const {},
  }) async {
    final t = await fw.RelayTransport.create(relayUrl: relayUrl, alias: alias);
    final info = await t.createRoom(fw.RoomConfig(
      maxPlayers: maxPlayers,
      schema: schema,
      canStartBeforeFull: true,
    ));
    _transport = t;
    _myNodeId = t.myNodeId;
    _roomCode = info.code;
    return info;
  }

  /// 玩家加入
  Future<void> joinRoom({
    required String relayUrl,
    required String alias,
    required String roomCode,
  }) async {
    final t = await fw.RelayTransport.create(relayUrl: relayUrl, alias: alias);
    await t.joinRoom(roomCode, '');
    _transport = t;
    _myNodeId = t.myNodeId;
    _roomCode = roomCode;
  }

  /// 订阅房间事件
  void subscribeRoom(String code) {
    final t = _transport;
    if (t == null) return;
    _sub?.cancel();
    _sub = t.subscribe('room/$code/events').listen((ev) {
      final p = ev.payload;
      if (p['type'] == 'peer-joined' || p['type'] == 'peer-online') {
        _eventsCtrl.add(PeerJoined(
          p['deviceId'] as String? ?? '',
          p['alias'] as String? ?? '',
        ));
      } else if (p['type'] == 'peer-left') {
        _eventsCtrl.add(PeerLeft(p['deviceId'] as String? ?? ''));
      } else if (p['type'] == 'message') {
        _eventsCtrl.add(MessageReceived(
          LocalnetMessage.fromTransportEvent(p),
        ));
      }
    });
  }

  /// 发送消息
  Future<void> sendMessage({
    required String text,
    Map<String, dynamic>? extra,
  }) async {
    final t = _transport;
    final code = _roomCode;
    if (t == null || code == null) return;
    final msg = LocalnetMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      fromNodeId: _myNodeId ?? '',
      fromAlias: '',
      text: text,
      ts: DateTime.now(),
      extra: extra,
    );
    await t.publish('room/$code/events', msg.toTransportPayload());
  }

  /// 发布自定义事件（发牌、状态变更等）
  Future<void> publish(Map<String, dynamic> payload) async {
    final t = _transport;
    final code = _roomCode;
    if (t == null || code == null) return;
    await t.publish('room/$code/events', payload);
  }

  /// 关闭连接
  Future<void> stop() async {
    await _sub?.cancel();
    await _transport?.close();
    _transport = null;
    _roomCode = null;
    _myNodeId = null;
    await _eventsCtrl.close();
  }
}

final localnetService = LocalnetService();
