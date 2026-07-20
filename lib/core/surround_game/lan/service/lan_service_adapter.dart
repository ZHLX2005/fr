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
import 'package:xiaodouzi_fr/core/localnet/channel/send_result.dart';
import 'package:xiaodouzi_fr/core/localnet/device/device.dart';
import 'package:xiaodouzi_fr/core/localnet/framework/framework_config.dart';
import 'package:xiaodouzi_fr/core/localnet/framework/lan_framework.dart';
import 'package:xiaodouzi_fr/core/localnet/session/session.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/protocol/lan_messages.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/persistence/player_profile_service.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/persistence/device_id_service.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/serializer/game_state_serializer.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/game_room.dart';
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

  Future<void> start({String? myAlias});
  Future<void> stop();
  bool get isRunning;

  void updateAlias(String newAlias);

  Stream<LanServiceError> watchErrors();

  String get myDeviceId;
  String get myAlias;

  Stream<List<Device>> watchDevices();

  Stream<LanRoomEvent> watchRoomEvents();
  Future<void> announceRoom(GameRoom room);
  Future<void> stopRoom(String roomId);

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
  void updateAlias(String newAlias) {
    if (newAlias.trim().isEmpty) return;
    _alias = newAlias.trim();
    PlayerProfileService.saveAlias(_alias);
  }

  @override
  Future<void> start({String? myAlias}) async {
    if (_isRunning) return;
    final persistedAlias = await PlayerProfileService.loadAlias();
    final aliasToUse = (myAlias != null && myAlias.isNotEmpty)
        ? myAlias
        : (persistedAlias ?? 'Player');
    if (myAlias != null && myAlias.isNotEmpty && myAlias != persistedAlias) {
      await PlayerProfileService.saveAlias(myAlias);
    }
    final deviceId = await DeviceIdService.load();
    _alias = aliasToUse;
    try {
      await _fw.start(FrameworkConfig(
        deviceAlias: aliasToUse,
        deviceId: deviceId,
      ));
      _isRunning = true;
      _multicastSub = _fw.watchMulticast().listen((msg) {
        final key = msg['key'] as String?;
        final payload = msg['payload'] as Map<String, dynamic>?;
        if (payload == null) return;

        if (key == 'room_announce' || key == 'room_join') {
          try {
            final ev = LanRoomEvent.fromJson(payload);
            _roomEventsCtrl.add(ev);
          } catch (e) {
            _errorsCtrl.add(
              LanServiceError('$key parse failed', cause: e),
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
  Future<void> stopRoom(String roomId) async {
    _announceTimers.remove(roomId)?.cancel();
    if (!_isRunning) return;
    // 广播关房，让 client 知道 host 已离开
    await _fw.sendMulticast(
      key: 'room_announce',
      payload: HostRoomClosed(roomId: roomId).toJson(),
    );
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
}
