// lib/core/jungle_chess/lan/protocol/lan_messages.dart
sealed class LanRoomEvent {
  String get type;
  Map<String, dynamic> toJson();

  static LanRoomEvent fromJson(Map<String, dynamic> json) {
    return switch (json['type'] as String) {
      'HostRoomAnnounced' => HostRoomAnnounced.fromJson(json),
      'HostRoomClosed' => HostRoomClosed.fromJson(json),
      'ClientJoinRequested' => ClientJoinRequested.fromJson(json),
      'ClientJoinResult' => ClientJoinResult.fromJson(json),
      'GameStartBroadcast' => GameStartBroadcast.fromJson(json),
      'HostClientLeft' => HostClientLeft.fromJson(json),
      'ClientDisconnectedProtocol' => ClientDisconnectedProtocol.fromJson(json),
      _ => throw FormatException('Unknown LAN event type: ${json['type']}'),
    };
  }
}

class HostRoomAnnounced extends LanRoomEvent {
  @override
  String get type => 'HostRoomAnnounced';
  final String hostDeviceId;
  final String hostName;
  final String roomId;

  HostRoomAnnounced({required this.hostDeviceId, required this.hostName, required this.roomId});

  @override
  Map<String, dynamic> toJson() => {'type': type, 'hostDeviceId': hostDeviceId, 'hostName': hostName, 'roomId': roomId};
  factory HostRoomAnnounced.fromJson(Map<String, dynamic> j) => HostRoomAnnounced(
    hostDeviceId: j['hostDeviceId'] as String,
    hostName: j['hostName'] as String,
    roomId: j['roomId'] as String,
  );
}

class HostRoomClosed extends LanRoomEvent {
  @override
  String get type => 'HostRoomClosed';
  HostRoomClosed();
  @override
  Map<String, dynamic> toJson() => {'type': type};
  factory HostRoomClosed.fromJson(Map<String, dynamic> j) => HostRoomClosed();
}

class ClientJoinRequested extends LanRoomEvent {
  @override
  String get type => 'ClientJoinRequested';
  final String clientDeviceId;
  final String clientAlias;

  ClientJoinRequested({required this.clientDeviceId, required this.clientAlias});

  @override
  Map<String, dynamic> toJson() => {'type': type, 'clientDeviceId': clientDeviceId, 'clientAlias': clientAlias};
  factory ClientJoinRequested.fromJson(Map<String, dynamic> j) => ClientJoinRequested(
    clientDeviceId: j['clientDeviceId'] as String,
    clientAlias: j['clientAlias'] as String,
  );
}

class ClientJoinResult extends LanRoomEvent {
  @override
  String get type => 'ClientJoinResult';
  final bool accepted;
  final String? rejectReason;

  ClientJoinResult({required this.accepted, this.rejectReason});

  @override
  Map<String, dynamic> toJson() => {'type': type, 'accepted': accepted, 'rejectReason': rejectReason};
  factory ClientJoinResult.fromJson(Map<String, dynamic> j) => ClientJoinResult(
    accepted: j['accepted'] as bool,
    rejectReason: j['rejectReason'] as String?,
  );
}

class GameStartBroadcast extends LanRoomEvent {
  @override
  String get type => 'GameStartBroadcast';
  final Map<String, dynamic> initialState;

  GameStartBroadcast({required this.initialState});

  @override
  Map<String, dynamic> toJson() => {'type': type, 'initialState': initialState};
  factory GameStartBroadcast.fromJson(Map<String, dynamic> j) => GameStartBroadcast(
    initialState: j['initialState'] as Map<String, dynamic>,
  );
}

class HostClientLeft extends LanRoomEvent {
  @override
  String get type => 'HostClientLeft';
  HostClientLeft();
  @override
  Map<String, dynamic> toJson() => {'type': type};
  factory HostClientLeft.fromJson(Map<String, dynamic> j) => HostClientLeft();
}

class ClientDisconnectedProtocol extends LanRoomEvent {
  @override
  String get type => 'ClientDisconnectedProtocol';
  final String message;
  ClientDisconnectedProtocol({this.message = ''});
  @override
  Map<String, dynamic> toJson() => {'type': type, 'message': message};
  factory ClientDisconnectedProtocol.fromJson(Map<String, dynamic> j) =>
    ClientDisconnectedProtocol(message: j['message'] as String? ?? '');
}
