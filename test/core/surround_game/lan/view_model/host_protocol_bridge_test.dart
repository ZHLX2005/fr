// test/core/surround_game/lan/view_model/host_protocol_bridge_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/lan_host_protocol_bridge.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/lan_match_state.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/protocol/lan_messages.dart';
import 'package:xiaodouzi_fr/core/surround_game/models/game_room.dart';
import 'package:xiaodouzi_fr/core/surround_game/engine/game_engine.dart';

void main() {
  group('reduceHostProtocol', () {
    final waiting = HostWaiting(GameRoom(
      roomId: 'r1',
      hostId: 'h1',
      hostName: 'Alice',
      hostIp: '0.0.0.0',
      createdAt: DateTime.parse('2026-06-15T00:00:00.000Z'),
    ));

    test('HostWaiting + ClientJoinRequested → HostWaiting with clientId/clientName', () {
      final ev = ClientJoinRequested(
        clientDeviceId: 'c1',
        clientAlias: 'Bob',
        roomId: 'r1',
      );
      final next = reduceHostProtocol(waiting, ev);
      expect(next, isA<HostWaiting>());
      final h = next as HostWaiting;
      expect(h.room.clientId, 'c1');
      expect(h.room.clientName, 'Bob');
    });

    test('HostInGame + HostClientLeft → HostError', () {
      final inGame = HostInGame(QuoridorEngine.initialize(), waiting.room);
      final ev = HostClientLeft();
      final next = reduceHostProtocol(inGame, ev);
      expect(next, isA<HostError>());
      final err = next as HostError;
      expect(err.message, '对手掉线');
      expect(err.previous, inGame);
    });

    test('其他状态 + 任意事件 → 状态不变', () {
      final lobby = const HostLobby();
      final ev = ClientJoinRequested(
        clientDeviceId: 'c1',
        clientAlias: 'Bob',
        roomId: 'r1',
      );
      expect(identical(reduceHostProtocol(lobby, ev), lobby), isTrue);
    });
  });
}
