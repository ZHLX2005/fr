import 'dart:async';

import 'package:flutter/material.dart';

import '../engine/game_engine.dart';
import '../local/local_match_state.dart';
import 'game_room.dart';
import '../models/game_state.dart';
import '../surround_game_constants.dart';
import 'lan_client_protocol_bridge.dart';
import 'lan_match_event.dart';
import 'lan_match_state.dart';
import 'protocol/lan_messages.dart';
import '../../localnet/device/device.dart' show Device;

final class LanClientViewModel extends ValueNotifier<LanClientState> {
  Timer? _countdownTimer;
  StreamSubscription<List<Device>>? _devicesSub;
  StreamSubscription<LanRoomEvent>? _roomSub;
  String? _peerDeviceId;

  LanClientViewModel({
    Stream<List<Device>>? devicesStream,
    Stream<LanRoomEvent>? roomEvents,
    String? peerDeviceId,
  }) : super(const ClientIdle()) {
    _peerDeviceId = peerDeviceId;
    if (devicesStream != null) {
      _devicesSub = devicesStream.listen(_onDevices);
    }
    if (roomEvents != null) {
      _roomSub = roomEvents.listen(_onRoomEvent);
    }
  }

  /// 在游戏开始时调用，设置对端 deviceId（用于 deviceLost 监听）
  void attachPeer(String peerDeviceId) {
    _peerDeviceId = peerDeviceId;
  }

  void _onDevices(List<Device> devices) {
    final peerId = _peerDeviceId;
    if (peerId == null) return;
    if (!devices.any((d) => d.deviceId == peerId)) {
      // 走协议路径（不走 dispatch，因为 ClientDisconnectedProtocol 是 LanRoomEvent 子类）
      _onRoomEvent(ClientDisconnectedProtocol());
    }
  }

  void _onRoomEvent(LanRoomEvent event) {
    final next = reduceClientProtocol(value, event);
    if (!identical(next, value)) {
      value = next;
    }
  }

  void dispatch(LanClientEvent event) {
    final next = reduce(value, event);
    if (!identical(next, value)) {
      value = next;
    }
  }

  LanClientState reduce(LanClientState s, LanClientEvent e) {
    return switch (e) {
      ClientJoinPressed(:final room) when s is ClientIdle =>
        ClientJoining(room),
      ClientJoinAccepted(:final room) when s is ClientJoining =>
        ClientWaiting(room),
      ClientJoinRejected() when s is ClientJoining => const ClientIdle(),
      HostStartedCountdown(:final secondsLeft) when s is ClientWaiting =>
        _startCountdown(s.room, secondsLeft),
      ClientTick() when s is ClientCountdown =>
        s.secondsLeft > 1
            ? ClientCountdown(s.room, s.secondsLeft - 1)
            : ClientInGame(QuoridorEngine.initialize(), s.room),
      ClientMoveCommitted(:final moveData) when s is ClientInGame =>
        _applyAndCheck(s, moveData),
      HostStatePushed(:final gameState) when s is ClientInGame =>
        ClientInGame(gameState, s.room),
      HostStatePushed(:final gameState) when s is ClientFinished =>
        ClientInGame(gameState, s.room),
      ClientReconnectPressed() when s is ClientDisconnected =>
        const ClientIdle(),
      _ => s,
    };
  }

  ClientCountdown _startCountdown(GameRoom room, int secondsLeft) {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      dispatch(const ClientTick());
    });
    return ClientCountdown(room, secondsLeft);
  }

  LanClientState _applyAndCheck(
    ClientInGame s,
    (int targetCellId, int? wallX, int? wallY,
        WallOrientation? wallOrientation) move,
  ) {
    GameState? result;
    if (move.$2 != null && move.$4 != null) {
      result =
          QuoridorEngine.placeWall(s.gameState, move.$2!, move.$3!, move.$4!);
    } else {
      result = QuoridorEngine.movePiece(s.gameState, move.$1);
    }
    if (result == null) return s;
    final next = QuoridorEngine.switchTurn(result);
    if (next.status == GameStatus.running) return ClientInGame(next, s.room);
    final gameResult = next.status == GameStatus.topWin
        ? GameResult.topWin
        : next.status == GameStatus.bottomWin
            ? GameResult.bottomWin
            : GameResult.draw;
    return ClientFinished(next, s.room, gameResult);
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _devicesSub?.cancel();
    _roomSub?.cancel();
    super.dispose();
  }
}
