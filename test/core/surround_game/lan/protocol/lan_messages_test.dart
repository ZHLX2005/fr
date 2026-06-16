// test/core/surround_game/lan/protocol/lan_messages_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/protocol/lan_messages.dart';
import 'package:xiaodouzi_fr/core/surround_game/models/game_room.dart';
import 'package:xiaodouzi_fr/core/surround_game/surround_game_constants.dart';

void main() {
  group('HostRoomAnnounced', () {
    test('round-trip toJson/fromJson', () {
      final room = GameRoom(
        roomId: 'r1',
        hostId: 'h1',
        hostName: 'Alice',
        hostIp: '192.168.1.10',
        hostPort: 53317,
        state: RoomState.waiting,
        createdAt: DateTime.parse('2026-06-15T10:00:00.000Z'),
      );
      final original = HostRoomAnnounced(
        room: room,
        hostDeviceId: 'h1',
        hostAlias: 'Alice',
      );
      final json = original.toJson();
      final restored = LanRoomEvent.fromJson(json) as HostRoomAnnounced;
      expect(restored.room.roomId, room.roomId);
      expect(restored.hostDeviceId, 'h1');
      expect(restored.hostAlias, 'Alice');
      expect(json['type'], 'HostRoomAnnounced');
    });
  });

  group('ClientJoinRequested', () {
    test('round-trip toJson/fromJson', () {
      final original = ClientJoinRequested(
        clientDeviceId: 'c1',
        clientAlias: 'Bob',
        roomId: 'r1',
      );
      final json = original.toJson();
      final restored = LanRoomEvent.fromJson(json) as ClientJoinRequested;
      expect(restored.clientDeviceId, 'c1');
      expect(restored.clientAlias, 'Bob');
      expect(restored.roomId, 'r1');
    });
  });

  group('ClientJoinResult', () {
    test('round-trip accepted=true', () {
      final original = ClientJoinResult(
        roomId: 'r1',
        clientDeviceId: 'c1',
        accepted: true,
      );
      final json = original.toJson();
      expect(json.containsKey('reason'), isFalse);
      final restored = LanRoomEvent.fromJson(json) as ClientJoinResult;
      expect(restored.accepted, isTrue);
      expect(restored.reason, isNull);
    });

    test('round-trip accepted=false with reason', () {
      final original = ClientJoinResult(
        roomId: 'r1',
        clientDeviceId: 'c1',
        accepted: false,
        reason: '房间已满',
      );
      final json = original.toJson();
      expect(json['reason'], '房间已满');
      final restored = LanRoomEvent.fromJson(json) as ClientJoinResult;
      expect(restored.accepted, isFalse);
      expect(restored.reason, '房间已满');
    });
  });

  group('fromJson', () {
    test('未知 type 抛 FormatException', () {
      expect(
        () => LanRoomEvent.fromJson({'type': 'Unknown'}),
        throwsFormatException,
      );
    });

    test('缺 type 抛 FormatException', () {
      expect(
        () => LanRoomEvent.fromJson({}),
        throwsFormatException,
      );
    });
  });
}
