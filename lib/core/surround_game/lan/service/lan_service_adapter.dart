// lib/core/surround_game/lan/service/lan_service_adapter.dart
//
// 业务层唯一接触 localnet 框架的边界。
// Page / ViewModel 不直接 import 'lib/core/localnet/...'。
//
// 内部维护：
//   - LanFramework.instance（启动 / 停止 / sendTo / watchChannel）
//   - StreamController<LanRoomEvent> 桥接多个 channel
//   - 周期性 announceRoom timer

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:xiaodouzi_fr/core/localnet/channel/channel_message.dart';
import 'package:xiaodouzi_fr/core/localnet/channel/send_result.dart';
import 'package:xiaodouzi_fr/core/localnet/device/device.dart';
import 'package:xiaodouzi_fr/core/localnet/framework/framework_config.dart';
import 'package:xiaodouzi_fr/core/localnet/framework/lan_framework.dart';
import 'package:xiaodouzi_fr/core/localnet/session/session.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/protocol/lan_channels.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/protocol/lan_messages.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/serializer/game_state_serializer.dart';
import 'package:xiaodouzi_fr/core/surround_game/models/game_room.dart';
import 'package:xiaodouzi_fr/core/surround_game/models/game_state.dart';

class LanServiceError {
  LanServiceError(this.message, {this.cause});
  final String message;
  final Object? cause;
  @override
  String toString() => 'LanServiceError($message)';
}

abstract class LanServiceAdapter {
  static final LanServiceAdapter instance = _LanServiceAdapterImpl();

  Future<void> start({required String myAlias});
  Future<void> stop();
  bool get isRunning;

  Stream<LanServiceError> watchErrors();
  String get myDeviceId;
  String get myAlias;

  Stream<List<Device>> watchDevices();

  Stream<LanRoomEvent> watchRoomEvents();
  Future<void> announceRoom(GameRoom room);
  void stopRoom(String roomId);

  Future<SendResult> sendJoinRequest({
    required String hostDeviceId,
    required String clientAlias,
  });
  Future<SendResult> sendJoinAccept({
    required String clientDeviceId,
    required GameRoom room,
  });

  Session<ValueNotifier<GameState>> createGameSession({
    required String peerDeviceId,
    required ValueNotifier<GameState> state,
    String? channelName,
  });
}

class _LanServiceAdapterImpl implements LanServiceAdapter {
  final LanFramework _fw = LanFramework.instance;
  final StreamController<LanServiceError> _errorsCtrl =
      StreamController<LanServiceError>.broadcast();
  final StreamController<LanRoomEvent> _roomEventsCtrl =
      StreamController<LanRoomEvent>.broadcast();

  final Map<String, Timer> _announceTimers = {};
  StreamSubscription<ChannelMessage>? _announceSub;
  StreamSubscription<ChannelMessage>? _joinSub;
  StreamSubscription<Map<String, dynamic>>? _multicastSub;

  bool _isRunning = false;
  String _alias = '';

  @override
  bool get isRunning => _isRunning;

  @override
  String get myDeviceId => _fw.myDeviceId;

  @override
  String get myAlias => _alias;

  @override
  Future<void> start({required String myAlias}) async {
    if (_isRunning) return;
    _alias = myAlias;
    try {
      await _fw.start(FrameworkConfig(deviceAlias: myAlias));
      _isRunning = true;
      _announceSub =
          _fw.watchChannel(LanChannels.roomAnnounce).listen(_onRoomAnnounce);
      _joinSub = _fw.watchChannel(LanChannels.roomJoin).listen(_onRoomJoin);
      _multicastSub = _fw.watchMulticast().listen((msg) {
        final key = msg['key'] as String?;
        final payload = msg['payload'] as Map<String, dynamic>?;
        if (payload == null) return;

        if (key == 'room_announce') {
          // 房间公告：所有设备都关心
          try {
            final ev = LanRoomEvent.fromJson(payload);
            _roomEventsCtrl.add(ev);
          } catch (e) {
            _errorsCtrl.add(
              LanServiceError('multicast announce parse failed', cause: e),
            );
          }
        } else if (key == 'room_join') {
          // Join 消息：只关心发给我的
          final toDeviceId = payload['toDeviceId'] as String?;
          if (toDeviceId == null || toDeviceId != myDeviceId) return;
          final innerPayload = Map<String, dynamic>.from(payload)
            ..remove('toDeviceId');
          try {
            final ev = LanRoomEvent.fromJson(innerPayload);
            _roomEventsCtrl.add(ev);
          } catch (e) {
            _errorsCtrl.add(
              LanServiceError('multicast join parse failed', cause: e),
            );
          }
        }
      });
    } catch (e) {
      _errorsCtrl.add(LanServiceError('framework start failed', cause: e));
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    if (!_isRunning) return;
    for (final t in _announceTimers.values) {
      t.cancel();
    }
    _announceTimers.clear();
    await _announceSub?.cancel();
    await _joinSub?.cancel();
    await _multicastSub?.cancel();
    await _fw.stop();
    _isRunning = false;
  }

  @override
  Stream<LanServiceError> watchErrors() => _errorsCtrl.stream;

  @override
  Stream<List<Device>> watchDevices() => _fw.watchDevices();

  @override
  Stream<LanRoomEvent> watchRoomEvents() => _roomEventsCtrl.stream;

  @override
  Future<void> announceRoom(GameRoom room) async {
    if (!_isRunning) return;
    final payload = HostRoomAnnounced(
      room: room,
      hostDeviceId: myDeviceId,
      hostAlias: _alias,
    ).toJson();
    _announceTimers[room.roomId]?.cancel();
    _announceTimers[room.roomId] =
        Timer.periodic(const Duration(seconds: 5), (_) => _sendOne(payload));
    // 立即发一次（走 UDP 多播）
    await _sendOne(payload);
  }

  @override
  void stopRoom(String roomId) {
    _announceTimers.remove(roomId)?.cancel();
  }

  Future<void> _sendOne(Map<String, dynamic> payload) async {
    if (!_isRunning) return;
    await _fw.sendMulticast(key: 'room_announce', payload: payload);
  }

  @override
  Future<SendResult> sendJoinRequest({
    required String hostDeviceId,
    required String clientAlias,
  }) {
    final payload = ClientJoinRequested(
      clientDeviceId: myDeviceId,
      clientAlias: clientAlias,
      roomId: '',
    ).toJson();
    return _fw.sendMulticast(key: 'room_join', payload: {
      'toDeviceId': hostDeviceId,
      ...payload,
    });
  }

  @override
  Future<SendResult> sendJoinAccept({
    required String clientDeviceId,
    required GameRoom room,
  }) {
    final payload = ClientJoinResult(
      roomId: room.roomId,
      clientDeviceId: clientDeviceId,
      accepted: true,
    ).toJson();
    return _fw.sendMulticast(key: 'room_join', payload: {
      'toDeviceId': clientDeviceId,
      ...payload,
    });
  }

  @override
  Session<ValueNotifier<GameState>> createGameSession({
    required String peerDeviceId,
    required ValueNotifier<GameState> state,
    String? channelName,
  }) {
    return _fw.createSession<ValueNotifier<GameState>>(
      peerId: peerDeviceId,
      state: state,
      serializer: const GameStateSerializer(),
      channelName: channelName,
    );
  }

  void _onRoomAnnounce(ChannelMessage msg) {
    try {
      final ev = LanRoomEvent.fromJson(msg.payload);
      _roomEventsCtrl.add(ev);
    } catch (e) {
      _errorsCtrl.add(LanServiceError('announce parse failed', cause: e));
    }
  }

  void _onRoomJoin(ChannelMessage msg) {
    try {
      final ev = LanRoomEvent.fromJson(msg.payload);
      _roomEventsCtrl.add(ev);
    } catch (e) {
      _errorsCtrl.add(LanServiceError('join parse failed', cause: e));
    }
  }
}
