/// LAN 模式的房间模型
///
/// 表示一个可发现的局域网游戏房间，由 Host 设备创建并通过局域网
/// 框架广播发现。包含房间元信息（ID、Host/Client 名称）与时间戳。
///
/// 配合 [LanServiceAdapter] 进行房间的创建、广播、加入与关闭。
/// 通过 [toJson]/[fromJson] 实现局域网多播序列化。
class GameRoom {
  final String roomId;
  final String hostId;
  final String hostName;
  final String? clientId;
  final String? clientName;

  const GameRoom({
    required this.roomId,
    required this.hostId,
    required this.hostName,
    this.clientId,
    this.clientName,
  });

  /// 占位房间工厂 — 在 Host 端尚未填齐 hostId/hostName 时
  /// 用本机 deviceId 与 alias 后续通过 [copyWith] 覆盖。
  factory GameRoom.placeholder({required String roomId}) => GameRoom(
        roomId: roomId,
        hostId: '',
        hostName: '',
      );

  GameRoom copyWith({
    String? roomId,
    String? hostId,
    String? hostName,
    String? clientId,
    String? clientName,
  }) {
    return GameRoom(
      roomId: roomId ?? this.roomId,
      hostId: hostId ?? this.hostId,
      hostName: hostName ?? this.hostName,
      clientId: clientId ?? this.clientId,
      clientName: clientName ?? this.clientName,
    );
  }

  Map<String, dynamic> toJson() => {
        'roomId': roomId,
        'hostId': hostId,
        'hostName': hostName,
        'clientId': clientId,
        'clientName': clientName,
      };

  factory GameRoom.fromJson(Map<String, dynamic> json) {
    return GameRoom(
      roomId: json['roomId'] as String,
      hostId: json['hostId'] as String,
      hostName: json['hostName'] as String? ?? 'Host',
      clientId: json['clientId'] as String?,
      clientName: json['clientName'] as String?,
    );
  }
}
