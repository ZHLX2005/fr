// test/core/surround_game/lan/view_model/client_protocol_bridge_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/lan_client_protocol_bridge.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/lan_match_state.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/protocol/lan_messages.dart';
import 'package:xiaodouzi_fr/core/surround_game/engine/game_engine.dart';
import 'package:xiaodouzi_fr/core/surround_game/models/game_room.dart';

void main() {
  group('reduceClientProtocol', () {
    final target = GameRoom(
      roomId: 'r1',
      hostId: 'h1',
      hostName: 'Alice',
      hostIp: '0.0.0.0',
      createdAt: DateTime.parse('2026-06-15T00:00:00.000Z'),
    );
    final joining = ClientJoining(target);

    test('Joining + ClientJoinResult(accepted=true) → Waiting', () {
      final ev = ClientJoinResult(
        roomId: 'r1',
        clientDeviceId: 'me',
        accepted: true,
      );
      final next = reduceClientProtocol(joining, ev);
      expect(next, isA<ClientWaiting>());
      final w = next as ClientWaiting;
      expect(w.room.roomId, 'r1');
    });

    test('Joining + ClientJoinResult(accepted=false) → Idle', () {
      final ev = ClientJoinResult(
        roomId: 'r1',
        clientDeviceId: 'me',
        accepted: false,
        reason: '房间已满',
      );
      final next = reduceClientProtocol(joining, ev);
      expect(next, isA<ClientIdle>());
    });

    test('InGame + ClientDisconnectedProtocol → Disconnected', () {
      final inGame = ClientInGame(QuoridorEngine.initialize(), target);
      final next = reduceClientProtocol(inGame, ClientDisconnectedProtocol());
      expect(next, isA<ClientDisconnected>());
    });

    test('其他状态 + 任意事件 → 状态不变', () {
      final idle = const ClientIdle();
      final ev = HostRoomAnnounced(
        room: target.copyWith(hostId: 'h2', hostName: 'Carol'),
        hostDeviceId: 'h2',
        hostAlias: 'Carol',
      );
      expect(identical(reduceClientProtocol(idle, ev), idle), isTrue);
    });
  });
}
