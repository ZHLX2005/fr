import 'dart:async';

import 'transport_event.dart';

/// 传输层抽象 — LAN/Relay 共性
///
/// ## 核心 API
///
/// - **events**: 事件总线原语（业务层订阅）
/// - **joinScope/watchScope**: 加入 scope 后自动同步（raft 风格最终一致）
/// - **emit**: 主动发布事件
///
/// ## 实现要求
///
/// - LAN ([LanTransport]): UDP 多播传输
/// - Relay ([RelayTransport]): HTTP 房间 + WebSocket
abstract class Transport {
  /// 节点身份（创建时随机生成或持久化）
  String get myNodeId;

  /// 事件总线原语 — 业务层用 `transport.events.where(...)` 订阅
  Stream<TransportEvent> get events;

  /// 当前加入的所有 scope
  Set<String> get activeScopes;

  /// 加入 scope（自动同步后续所有变更）
  Future<void> joinScope(String scope);

  /// 离开 scope
  void leaveScope(String scope);

  /// 订阅 scope 的最终一致状态
  Stream<DataLog> watchScope(String scope);

  /// 当前 scope 的最终一致状态（null 表示未加入）
  DataLog? getScope(String scope);

  /// 广播当前 scope 的全量状态给所有在该 scope 的其他节点
  ///
  /// 调用者应先通过 [getScope] 获取 DataLog，修改 state 后调用此方法。
  Future<void> broadcastScope(String scope);

  /// 主动发布事件到 events 流（仅本地，不广播）
  void emit(TransportEvent event);

  /// 广播事件到所有对端（type='event'）
  ///
  /// 业务层用 [events] 订阅接收。
  Future<void> broadcastEvent(String topic, Map<String, dynamic> data);

  /// 启动传输
  Future<void> start();

  /// 停止传输
  Future<void> stop();
}

/// scope 内的最终一致状态
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

  /// 状态变更流（本地 + 远端）
  Stream<DataLog> get onUpdate => _ctrl.stream;

  /// 本地变更（标记 fromNodeId = 本节点）
  void merge(Map<String, dynamic> delta, {required String localNodeId}) {
    state.addAll(delta);
    fromNodeId = localNodeId;
    _ctrl.add(this);
  }

  /// 收到对端变更（应用）
  void applyRemote(DataLog remote) {
    state = Map<String, dynamic>.from(remote.state);
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