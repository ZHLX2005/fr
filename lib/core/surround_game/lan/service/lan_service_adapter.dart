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
import 'package:xiaodouzi_fr/core/surround_game/engine/game_engine.dart';
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
  });

  Future<SendResult> sendGameState({
    required String hostDeviceId,
    required GameState state,
  });

  Stream<GameState> watchGameState(String hostDeviceId);
}

class _LanServiceAdapterImpl implements LanServiceAdapter {
  final LanFramework _fw = LanFramework.instance;
  final StreamController<LanServiceError> _errorsCtrl =
      StreamController<LanServiceError>.broadcast();
  final StreamController<LanRoomEvent> _roomEventsCtrl =
      StreamController<LanRoomEvent>.broadcast();
  final StreamController<GameState> _gameStateCtrl =
      StreamController<GameState>.broadcast();

  final Map<String, Timer> _announceTimers = {};
  StreamSubscription<ChannelMessage>? _announceSub;
  StreamSubscription<ChannelMessage>? _joinSub;
  StreamSubscription<ChannelMessage>? _gameStateSub;
  final Map<String, Stream<GameState>> _gameStateStreams = {};

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
      _gameStateSub = _fw
          .watchChannel(LanChannels.gameState)
          .listen(_onGameStateMessage);
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
    await _gameStateSub?.cancel();
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
    // 立即发一次
    await _sendOne(payload);
  }

  @override
  void stopRoom(String roomId) {
    _announceTimers.remove(roomId)?.cancel();
  }

  Future<void> _sendOne(Map<String, dynamic> payload) async {
    if (!_isRunning) return;
    final devices = _fw.devices;
    for (final d in devices) {
      await _fw.sendTo(
        d.deviceId,
        LanChannels.roomAnnounce,
        payload,
      );
    }
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
    return _fw.sendTo(hostDeviceId, LanChannels.roomJoin, payload);
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
    return _fw.sendTo(clientDeviceId, LanChannels.roomJoin, payload);
  }

  @override
  Session<ValueNotifier<GameState>> createGameSession({
    required String peerDeviceId,
    required ValueNotifier<GameState> state,
  }) {
    return _fw.createSession<ValueNotifier<GameState>>(
      peerId: peerDeviceId,
      state: state,
      serializer: const GameStateSerializer(),
    );
  }

  @override
  Future<SendResult> sendGameState({
    required String hostDeviceId,
    required GameState state,
  }) {
    return _fw.sendTo(
      hostDeviceId,
      LanChannels.gameState,
      state.toJson(),
    );
  }

  @override
  Stream<GameState> watchGameState(String hostDeviceId) {
    return _gameStateStreams.putIfAbsent(
      hostDeviceId,
      () {
        // 简单实现：所有 game state 推同一流，调用方按 hostDeviceId 过滤
        return _gameStateCtrl.stream;
      },
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

  void _onGameStateMessage(ChannelMessage msg) {
    try {
      final temp = GameState.fromJson(msg.payload);
      final rebuilt = QuoridorEngine.replayHistory(temp.history);
      _gameStateCtrl.add(rebuilt);
    } catch (e) {
      _errorsCtrl.add(LanServiceError('game state parse failed', cause: e));
    }
  }
}
