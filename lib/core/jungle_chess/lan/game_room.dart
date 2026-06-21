// lib/core/jungle_chess/lan/game_room.dart
class GameRoom {
  final String roomId;
  final String hostDeviceId;
  final String hostName;
  final String? clientDeviceId;
  final String? clientName;

  const GameRoom({
    required this.roomId, required this.hostDeviceId, required this.hostName,
    this.clientDeviceId, this.clientName,
  });

  bool get hasClient => clientDeviceId != null;

  GameRoom copyWith({String? roomId, String? hostDeviceId, String? hostName, String? clientDeviceId, String? clientName}) {
    return GameRoom(
      roomId: roomId ?? this.roomId,
      hostDeviceId: hostDeviceId ?? this.hostDeviceId,
      hostName: hostName ?? this.hostName,
      clientDeviceId: clientDeviceId ?? this.clientDeviceId,
      clientName: clientName ?? this.clientName,
    );
  }

  Map<String, dynamic> toJson() => {
    'roomId': roomId, 'hostDeviceId': hostDeviceId, 'hostName': hostName,
    'clientDeviceId': clientDeviceId, 'clientName': clientName,
  };

  factory GameRoom.fromJson(Map<String, dynamic> j) => GameRoom(
    roomId: j['roomId'] as String,
    hostDeviceId: j['hostDeviceId'] as String,
    hostName: j['hostName'] as String,
    clientDeviceId: j['clientDeviceId'] as String?,
    clientName: j['clientName'] as String?,
  );

  @override
  String toString() => 'GameRoom($hostName/$roomId)';
}
