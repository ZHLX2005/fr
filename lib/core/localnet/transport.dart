import 'dart:async';

/// 房间配置 — master 创建时定义
class RoomConfig {
  RoomConfig({
    this.maxPlayers = 2,
    this.schema = const {},
    this.canStartBeforeFull = true,
    this.autoStartThreshold = 0,
  });

  /// 房间最大人数（默认 2，可扩展到 3+ 多人）
  final int maxPlayers;

  /// master 定义的 schema（卡牌配置、状态字段等）
  final Map<String, dynamic> schema;

  /// 房间未满时是否允许 master 主动开局
  final bool canStartBeforeFull;

  /// 人数达到此值时自动开局（0 = 不自动）
  final int autoStartThreshold;
}

/// 房间信息
class RoomInfo {
  RoomInfo({
    required this.code,
    required this.hostNodeId,
    required this.maxPlayers,
    required this.token,
  });
  final String code;
  final String hostNodeId;
  final int maxPlayers;

  /// 房间 token（加入 / subscribe 时需要）
  final String token;
}

/// 远端事件 — 来自 topic 的消息
class RemoteEvent {
  RemoteEvent({
    required this.topic,
    required this.fromNodeId,
    required this.payload,
  });
  final String topic;
  final String fromNodeId;
  final Map<String, dynamic> payload;
}

/// 节点在房间中的角色
enum NodeRole { unknown, host, client }

/// scope 内最终一致状态（旧 API，兼容保留）
class DataLog {
  DataLog({
    required this.scope,
    Map<String, dynamic>? initialState,
    this.fromNodeId = '',
  }) : state = Map<String, dynamic>.from(initialState ?? const {});

  final String scope;
  Map<String, dynamic> state;
  String fromNodeId;

  final StreamController<DataLog> _ctrl =
      StreamController<DataLog>.broadcast();

  Stream<DataLog> get onUpdate => _ctrl.stream;

  void merge(Map<String, dynamic> delta, {required String localNodeId}) {
    state.addAll(delta);
    fromNodeId = localNodeId;
    _ctrl.add(this);
  }

  void applyRemote(DataLog remote) {
    state.addAll(remote.state);
    fromNodeId = remote.fromNodeId;
    _ctrl.add(this);
  }

  Map<String, dynamic> toJson() => {
        'scope': scope,
        'state': state,
        'from': fromNodeId,
      };

  factory DataLog.fromJson(Map<String, dynamic> json) => DataLog(
        scope: json['scope'] as String,
        initialState:
            (json['state'] as Map?)?.cast<String, dynamic>() ?? const {},
        fromNodeId: json['from'] as String? ?? '',
      );

  Future<void> dispose() async {
    await _ctrl.close();
  }
}

/// 旧传输事件总线原语（保留兼容）
class TransportEvent {
  const TransportEvent({
    required this.topic,
    required this.data,
    required this.timestamp,
  });
  final String topic;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
        'topic': topic,
        'data': data,
        'ts': timestamp.toIso8601String(),
      };

  factory TransportEvent.fromJson(Map<String, dynamic> json) => TransportEvent(
        topic: json['topic'] as String? ?? '',
        data: (json['data'] as Map?)?.cast<String, dynamic>() ?? const {},
        timestamp: DateTime.tryParse(json['ts'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// 传输层抽象 — pub/sub 通道（v2）
///
/// ## 核心 API（v2 — 推荐）
///
/// - **myNodeId**: 本节点身份
/// - **subscribe(topic)**: 订阅一个 topic
/// - **publish(topic, payload)**: 发布到 topic
/// - **createRoom(config)**: 创建一个房间
/// - **joinRoom(code, token)**: 加入已有房间
///
/// ## 旧 API（v1 — 兼容保留，业务层迁移后会删除）
///
/// - joinScope / leaveScope / getScope / watchScope / broadcastScope
/// - sendEvent / events
/// - activeScopes
///
/// v2 实现应同时实现 v1 方法（用 topic 模拟 scope）。
abstract class Transport {
  /// 本节点身份
  String get myNodeId;

  /// 本节点创建时间（microsecond）
  int get myCreatedAt;

  /// 本节点在当前房间中的角色
  NodeRole get myRole;

  /// 设置本节点角色
  void setRole(NodeRole role);

  /// 已确认的对端 nodeId
  String? get peerNodeId;

  /// 设置对端 nodeId
  void setPeerNodeId(String? nodeId);

  /// 对端的角色
  NodeRole get peerRole;

  /// 设置对端角色
  void setPeerRole(NodeRole role);

  // ---------------- v2 pub/sub API ----------------

  /// 当前连接状态
  bool get isConnected;

  /// 连接到传输层
  Future<void> connect();

  /// 关闭连接
  Future<void> close();

  /// 订阅 topic
  Stream<RemoteEvent> subscribe(String topic);

  /// 取消订阅
  Future<void> unsubscribe(String topic);

  /// 发布到 topic
  Future<void> publish(String topic, Map<String, dynamic> payload);

  /// 创建房间（master）
  Future<RoomInfo> createRoom(RoomConfig config);

  /// 加入房间（带 token）
  Future<void> joinRoom(String code, String token);

  /// 离开房间
  Future<void> leaveRoom(String code);

  // ---------------- v1 scope API（兼容保留）----------------

  /// 事件总线原语
  @Deprecated('use subscribe(topic) + publish(topic, payload)')
  Stream<TransportEvent> get events;

  /// 当前加入的所有 scope
  @Deprecated('use subscribe() to track topics explicitly')
  Set<String> get activeScopes;

  /// 加入 scope
  @Deprecated('use subscribe() instead')
  Future<void> joinScope(String scope);

  /// 离开 scope
  @Deprecated('use unsubscribe() instead')
  void leaveScope(String scope);

  /// 订阅 scope 的最终一致状态
  @Deprecated('use subscribe() + RemoteEvent stream instead')
  Stream<DataLog> watchScope(String scope);

  /// 当前 scope 的最终一致状态
  @Deprecated('scope-based state will be removed in v3')
  DataLog? getScope(String scope);

  /// 广播 scope 状态
  @Deprecated('use publish() with a state-snapshot topic instead')
  Future<void> broadcastScope(String scope);

  /// 通过事件总线发送一条事件
  @Deprecated('use publish() instead')
  Future<void> sendEvent(String scope, String topic, Map<String, dynamic> data);

  /// 主动发布事件到 events 流
  @Deprecated('use subscribe() pattern instead')
  void emit(TransportEvent event);

  /// 启动传输
  @Deprecated('use connect()')
  Future<void> start();

  /// 停止传输
  @Deprecated('use close()')
  Future<void> stop();
}