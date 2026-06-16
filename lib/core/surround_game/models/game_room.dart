/// 游戏房间模型
///
/// 表示一个可发现的局域网游戏房间，由 Host 设备创建并通过 UDP
/// 广播发现。包含房间元信息（ID、Host/Client 名称、IP/端口）、
/// 房间状态（waiting/playing/closed）及时间戳。
///
/// 配合 [SurroundGameService] 进行房间的创建、加入、发现和同步。
/// 通过 [toJson]/[fromJson] 实现 UDP 广播序列化。
import '../surround_game_constants.dart';

/// 游戏房间模型
class GameRoom {
  final String roomId;
  final String hostId;
  final String hostName;
  final String hostIp;
  final int hostPort;
  final String? clientId;
  final String? clientName;
  final RoomState state;
  final DateTime createdAt;

  const GameRoom({
    required this.roomId,
    required this.hostId,
    required this.hostName,
    required this.hostIp,
    this.hostPort = 53317,
    this.clientId,
    this.clientName,
    this.state = RoomState.waiting,
    required this.createdAt,
  });

  /// 占位房间工厂（本轮 LAN 桩化用）
  ///
  /// 创建一个表示"主机已建房"但尚未连接后端的占位房间对象。
  factory GameRoom.placeholder({required String roomId}) => GameRoom(
        roomId: roomId,
        hostId: 'host',
        hostName: '主机',
        hostIp: '0.0.0.0',
        hostPort: 53317,
        state: RoomState.waiting,
        createdAt: DateTime.now(),
      );

  /// 当前玩家数
  int get playerCount => (hostId.isNotEmpty ? 1 : 0) + (clientId != null ? 1 : 0);

  /// 最大玩家数
  int get maxPlayers => SurroundGameConstants.kMaxPlayers;

  /// 是否已满
  bool get isFull => playerCount >= maxPlayers;

  /// 当前房间是否包含指定玩家
  bool containsPlayer(String playerId) =>
      hostId == playerId || clientId == playerId;

  GameRoom copyWith({
    String? roomId,
    String? hostId,
    String? hostName,
    String? hostIp,
    int? hostPort,
    String? clientId,
    String? clientName,
    RoomState? state,
    DateTime? createdAt,
  }) {
    return GameRoom(
      roomId: roomId ?? this.roomId,
      hostId: hostId ?? this.hostId,
      hostName: hostName ?? this.hostName,
      hostIp: hostIp ?? this.hostIp,
      hostPort: hostPort ?? this.hostPort,
      clientId: clientId ?? this.clientId,
      clientName: clientName ?? this.clientName,
      state: state ?? this.state,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'roomId': roomId,
    'hostId': hostId,
    'hostName': hostName,
    'hostIp': hostIp,
    'hostPort': hostPort,
    'clientId': clientId,
    'clientName': clientName,
    'state': state.name,
    'createdAt': createdAt.toIso8601String(),
  };

  factory GameRoom.fromJson(Map<String, dynamic> json) {
    return GameRoom(
      roomId: json['roomId'] as String,
      hostId: json['hostId'] as String,
      hostName: json['hostName'] as String? ?? 'Host',
      hostIp: json['hostIp'] as String? ?? '',
      hostPort: json['hostPort'] as int? ?? 53317,
      clientId: json['clientId'] as String?,
      clientName: json['clientName'] as String?,
      state: RoomState.values.firstWhere(
        (e) => e.name == json['state'],
        orElse: () => RoomState.waiting,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
