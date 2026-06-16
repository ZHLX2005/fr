import 'dart:async';

import 'package:flutter/material.dart';

import '../engine/game_engine.dart';
import '../local/local_match_state.dart';
import '../models/game_room.dart';
import '../models/game_state.dart';
import '../surround_game_constants.dart';
import 'lan_match_event.dart';
import 'lan_match_state.dart';
import 'lan_host_protocol_bridge.dart';
import 'protocol/lan_messages.dart' as proto show LanRoomEvent, HostClientLeft;
import '../../localnet/device/device.dart' show Device;

final class LanHostViewModel extends ValueNotifier<LanHostState> {
  Timer? _countdownTimer;
  StreamSubscription<List<Device>>? _devicesSub;
  StreamSubscription<proto.LanRoomEvent>? _roomSub;
  String? _peerDeviceId;

  LanHostViewModel({
    Stream<List<Device>>? devicesStream,
    Stream<proto.LanRoomEvent>? roomEvents,
    String? peerDeviceId,
  }) : super(const HostLobby()) {
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
      // 走协议路径（不走 dispatch，因为 HostClientLeft 在 lan_messages 中作为
      // LanRoomEvent 子类定义，由 reduceHostProtocol 统一处理）。
      _onRoomEvent(proto.HostClientLeft());
    }
  }

  void _onRoomEvent(proto.LanRoomEvent event) {
    final next = reduceHostProtocol(value, event);
    if (!identical(next, value)) {
      value = next;
    }
  }

  void dispatch(LanHostEvent event) {
    final next = reduce(value, event);
    if (!identical(next, value)) {
      value = next;
    }
  }

  LanHostState reduce(LanHostState s, LanHostEvent e) {
    return switch (e) {
      HostCreateRoomPressed() when s is HostLobby =>
        HostWaiting(GameRoom.placeholder(
          roomId: 'room-${DateTime.now().millisecondsSinceEpoch}',
        )),
      HostCreateRoomWithRoom(:final room) when s is HostLobby =>
        HostWaiting(room),
      HostClientJoined(:final clientId, :final clientName)
          when s is HostWaiting =>
        HostWaiting(s.room.copyWith(
          clientId: clientId,
          clientName: clientName,
        )),
      HostStartGamePressed() when s is HostWaiting =>
        _startCountdown(s.room),
      HostStartGamePressed() when s is HostFinished =>
        _startCountdown(s.room),
      HostTick() when s is HostCountdown =>
        s.secondsLeft > 0
            ? HostCountdown(s.room, s.secondsLeft - 1)
            : HostInGame(QuoridorEngine.initialize(), s.room),
      HostMoveReceived(:final moveData) when s is HostInGame =>
        _applyAndCheck(s, moveData),
      HostMoveCommitted(:final moveData) when s is HostInGame =>
        _applyAndCheck(s, moveData),
      HostAbortGame() when s is HostError => value,
      HostAbortGame() => s,
      HostRetryPressed() when s is HostError =>
        s.previous ?? const HostLobby(),
      _ => s,
    };
  }

  HostCountdown _startCountdown(GameRoom room) {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      dispatch(const HostTick());
    });
    return HostCountdown(room, 3);
  }

  LanHostState _applyAndCheck(
    HostInGame s,
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
    if (next.status == GameStatus.running) return HostInGame(next, s.room);
    // Determine result
    final gameResult = next.status == GameStatus.topWin
        ? GameResult.topWin
        : next.status == GameStatus.bottomWin
            ? GameResult.bottomWin
            : GameResult.draw;
    return HostFinished(next, s.room, gameResult);
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _devicesSub?.cancel();
    _roomSub?.cancel();
    super.dispose();
  }
}
