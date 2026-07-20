// lib/core/surround_game/lan/service/lan_service_adapter.dart
//
// 业务层唯一接触 localnet 框架的边界。
// 同时支持 LAN（UDP 多播发现 + HTTP P2P）和 Relay（房间号发现 + WS 通讯）。
//
// LAN 模式：all-in adapter 内部通过 multicast / Session 管理
// Relay 模式：createChatRoom/joinChatRoom 建立 WS 连接，协议消息走 transport.sendTo/watchChannel

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:xiaodouzi_fr/core/localnet/channel/send_result.dart';
import 'package:xiaodouzi_fr/core/localnet/device/device.dart';
import 'package:xiaodouzi_fr/core/localnet/framework/framework_config.dart';
import 'package:xiaodouzi_fr/core/localnet/framework/lan_framework.dart';
import 'package:xiaodouzi_fr/core/localnet/session/session.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/transport_kind.dart';
import 'package:xiaodouzi_fr/core/localnet/transport_service/transport_service.dart';
import '../protocol/lan_messages.dart';
import '../persistence/player_profile_service.dart';
import '../persistence/device_id_service.dart';
import '../serializer/game_state_serializer.dart';
import '../game_room.dart';
import '../../models/game_state.dart';

class LanServiceError {
  LanServiceError(this.message, {this.cause});
  final String message;
  final Object? cause;
  @override
  String toString() => 'LanServiceError($message)';
}

abstract class LanServiceAdapter {
  static final LanServiceAdapter instance = _GameServiceAdapterImpl();

  Future<void> start({String? myAlias, TransportKind kind = TransportKind.lan});
  Future<void> stop();
  bool get isRunning;
  TransportKind get transportKind;
  String? get currentRoomCode;

  void updateAlias(String newAlias);

  Stream<LanServiceError> watchErrors();

  String get myDeviceId;
  String get myAlias;

  Stream<List<Device>> watchDevices();

  // === 房间事件流（LAN: multicast → parsed; Relay: WS channel → parsed） ===
  Stream<LanRoomEvent> watchRoomEvents();

  // === 房间生命周期 ===
  /// LAN: 开始周期 UDP 广播; Relay: 创建房间 + 建立 WS
  Future<String> createRoom(GameRoom room);
  /// Relay 专用：加入房间（LAN 用 sendJoinRequest）
  Future<void> joinRelayRoom(String roomCode,
      {required String hostDeviceId, required String hostAlias});
  /// 停止广播 / 离开房间
  Future<void> closeRoom(String roomId);

  // === 协议消息（LAN: multicast; Relay: WS sendTo） ===
  Future<SendResult> sendJoinRequest({
    required String hostDeviceId,
    required String clientAlias,
  });
  Future<SendResult> sendJoinAccept({
    required String clientDeviceId,
    required GameRoom room,
  });
  /// Relay 模式：通知对端游戏开始（倒计时结束）
  Future<void> sendGameStart(String peerDeviceId, GameRoom room);

  // === 游戏状态同步 ===
  /// LAN 模式：Session（HTTP P2P）; Relay 模式：直接 sendTo/watchChannel
  Session<ValueNotifier<GameState>> createGameSession({
    required String peerDeviceId,
    required ValueNotifier<GameState> state,
    String? channelName,
  });
  /// Relay 模式专用：替代 Session 的游戏状态同步（WS 帧）
  StreamSubscription<TransportMessage> startRelayGameSync({
    required String peerDeviceId,
    required ValueNotifier<GameState> state,
    required void Function() onChanged,
  });
  /// 发送游戏状态变更（Relay 模式）
  Future<void> sendRelayGameState(String peerDeviceId, GameState state);
}

class _GameServiceAdapterImpl implements LanServiceAdapter {
  final LanFramework _fw = LanFramework.instance;
  final StreamController<LanServiceError> _errorsCtrl =
      StreamController<LanServiceError>.broadcast();
  final StreamController<LanRoomEvent> _roomEventsCtrl =
      StreamController<LanRoomEvent>.broadcast();

  final Map<String, Timer> _announceTimers = {};
  StreamSubscription<Map<String, dynamic>>? _multicastSub;
  StreamSubscription<TransportMessage>? _relayRoomSub;

  bool _isRunning = false;
  TransportKind _kind = TransportKind.lan;
  String _alias = '';

  @override
  bool get isRunning => _isRunning;

  @override
  TransportKind get transportKind => _kind;

  @override
  String? get currentRoomCode => _fw.currentRoomCode;

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
  Future<void> start({String? myAlias, TransportKind kind = TransportKind.lan}) async {
    if (_isRunning) return;
    _kind = kind;

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
      final config = FrameworkConfig(
        deviceAlias: aliasToUse,
        deviceId: deviceId,
        transportKind: kind,
        relayUrl: kind == TransportKind.relay ? 'http://47.110.80.47:8988' : null,
        httpServerEnabled: kind != TransportKind.relay,
        udpListenerEnabled: kind != TransportKind.relay,
        udpBroadcastEnabled: kind != TransportKind.relay,
      );
      await _fw.start(config);
      _isRunning = true;

      if (_kind == TransportKind.relay) {
        _subscribeRelay();
      } else {
        _subscribeLan();
      }
    } catch (e) {
      _errorsCtrl.add(LanServiceError('framework start failed', cause: e));
      rethrow;
    }
  }

  void _subscribeLan() {
    _multicastSub = _fw.watchMulticast().listen((msg) {
      final key = msg['key'] as String?;
      final payload = msg['payload'] as Map<String, dynamic>?;
      if (payload == null) return;

      if (key == 'room_announce' || key == 'room_join') {
        try {
          final ev = LanRoomEvent.fromJson(payload);
          _roomEventsCtrl.add(ev);
        } catch (e) {
          _errorsCtrl.add(LanServiceError('$key parse failed', cause: e));
        }
      }
    });
  }

  void _subscribeRelay() {
    // Relay 模式：协议消息走 watchChannel('surround/game')
    _relayRoomSub = _fw.watchChannel('surround/game').listen((msg) {
      final ev = LanRoomEvent.fromJson(msg.payload);
      _roomEventsCtrl.add(ev);
    }, onError: (e) {
      _errorsCtrl.add(LanServiceError('relay parse failed', cause: e));
    });
  }

  @override
  Future<void> stop() async {
    if (!_isRunning) return;
    _kind = TransportKind.lan;
    for (final t in _announceTimers.values) {
      t.cancel();
    }
    _announceTimers.clear();
    await _multicastSub?.cancel();
    await _relayRoomSub?.cancel();
    await _fw.stop();
    _isRunning = false;
  }

  @override
  Stream<LanServiceError> watchErrors() => _errorsCtrl.stream;

  @override
  Stream<List<Device>> watchDevices() => _fw.watchDevices();

  @override
  Stream<LanRoomEvent> watchRoomEvents() => _roomEventsCtrl.stream;

  // ============ 房间生命周期 ============

  @override
  Future<String> createRoom(GameRoom room) async {
    if (_kind == TransportKind.relay) {
      // Relay：创建服务器房间 → 返回 roomCode
      final code = await _fw.createChatRoom();
      // 首次连接建立后，RSVP: 广播 room announce 给 WS 通道
      final payload = HostRoomAnnounced(
        room: room.copyWith(hostId: myDeviceId, hostName: _alias),
        hostDeviceId: myDeviceId,
        hostAlias: _alias,
      ).toJson();
      await _fw.sendTo('relay', 'surround/game', payload);
      return code;
    }
    // LAN：开始周期 UDP 多播广播
    final payload = HostRoomAnnounced(
      room: room,
      hostDeviceId: myDeviceId,
      hostAlias: _alias,
    ).toJson();
    _announceTimers[room.roomId]?.cancel();
    _announceTimers[room.roomId] =
        Timer.periodic(const Duration(seconds: 5), (_) => _sendMulticastOne(payload));
    await _sendMulticastOne(payload);
    return room.roomId;
  }

  @override
  Future<void> joinRelayRoom(String roomCode,
      {required String hostDeviceId, required String hostAlias}) async {
    // Relay：通过房间 WS 加入
    await _fw.joinChatRoom(roomCode);
    // 立即发送 join 请求（走 WS）
    final payload = ClientJoinRequested(
      clientDeviceId: myDeviceId,
      clientAlias: _alias,
      roomId: roomCode,
    ).toJson();
    await _fw.sendTo(hostDeviceId, 'surround/game', payload);
  }

  @override
  Future<void> closeRoom(String roomId) async {
    if (_kind == TransportKind.relay) {
      await _fw.leaveChatRoom();
      return;
    }
    _announceTimers.remove(roomId)?.cancel();
    if (!_isRunning) return;
    await _fw.sendMulticast(
      key: 'room_announce',
      payload: HostRoomClosed(roomId: roomId).toJson(),
    );
  }

  Future<void> _sendMulticastOne(Map<String, dynamic> payload) async {
    if (!_isRunning) return;
    await _fw.sendMulticast(key: 'room_announce', payload: payload);
  }

  // ============ 协议消息 ============

  @override
  Future<SendResult> sendJoinRequest({
    required String hostDeviceId,
    required String clientAlias,
  }) async {
    final payload = ClientJoinRequested(
      clientDeviceId: myDeviceId,
      clientAlias: clientAlias,
      roomId: '',
    ).toJson();

    if (_kind == TransportKind.relay) {
      return await _fw.sendTo(hostDeviceId, 'surround/game', payload);
    }
    return await _fw.sendMulticast(key: 'room_join', payload: {
      'toDeviceId': hostDeviceId,
      ...payload,
    });
  }

  @override
  Future<SendResult> sendJoinAccept({
    required String clientDeviceId,
    required GameRoom room,
  }) async {
    final payload = ClientJoinResult(
      roomId: room.roomId,
      clientDeviceId: clientDeviceId,
      accepted: true,
    ).toJson();

    if (_kind == TransportKind.relay) {
      return await _fw.sendTo(clientDeviceId, 'surround/game', payload);
    }
    return await _fw.sendMulticast(key: 'room_join', payload: {
      'toDeviceId': clientDeviceId,
      ...payload,
    });
  }

  @override
  Future<void> sendGameStart(String peerDeviceId, GameRoom room) async {
    if (_kind != TransportKind.relay) return;
    // Relay 模式：通知对端游戏已开始
    await _fw.sendTo(peerDeviceId, 'surround/game', {
      'type': 'GameStart',
      'roomId': room.roomId,
    });
  }

  // ============ 游戏状态同步 ============

  @override
  Session<ValueNotifier<GameState>> createGameSession({
    required String peerDeviceId,
    required ValueNotifier<GameState> state,
    String? channelName,
  }) {
    // LAN 模式：走 Session（HTTP P2P）
    return _fw.createSession<ValueNotifier<GameState>>(
      peerId: peerDeviceId,
      state: state,
      serializer: const GameStateSerializer(),
      channelName: channelName,
    );
  }

  @override
  StreamSubscription<TransportMessage> startRelayGameSync({
    required String peerDeviceId,
    required ValueNotifier<GameState> state,
    required void Function() onChanged,
  }) {
    // Relay 模式：直接订阅 WS game state 通道
    final sub = _fw.watchChannel('surround/game/state').listen((msg) {
      final gs = GameState.fromJson(msg.payload);
      state.value = gs;
      onChanged();
    });
    return sub;
  }

  @override
  Future<void> sendRelayGameState(String peerDeviceId, GameState gameState) async {
    await _fw.sendTo(peerDeviceId, 'surround/game/state', gameState.toJson());
  }
}
