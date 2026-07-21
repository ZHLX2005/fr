import 'dart:async';

import 'transport_event.dart';

/// 节点在房间中的角色
///
/// Discovery widget 完成 HTTP 握手后，应用层会调用 [Transport.setRole]
/// 声明自己的角色（通常是 host 或 client）。
enum NodeRole {
  /// 角色未声明（初始状态，握手未完成）
  unknown,

  /// 房主 / 邀请方
  host,

  /// 加入者 / 受邀方
  client,
}

/// 传输层抽象 — LAN/Relay 共性
///
/// ## 核心 API
///
/// - **myNodeId / myRole / peerNodeId**: 本节点身份 + 在房间中的角色 + 对端身份
/// - **events**: 事件总线原语（业务层订阅）
/// - **joinScope/watchScope/broadcastScope**: scope 内最终一致状态同步
///
/// ## 角色协商
///
/// 1. Discovery widget 完成 HTTP 三次握手
/// 2. 应用层根据业务逻辑（如 surround_game 邀请/接受方向）调用 [setRole] 声明角色
/// 3. DataLog 完全用于业务数据（游戏状态、房间成员列表等），不再承担身份推断
///
/// 实现要求：
/// - LAN ([LanTransport]): UDP 多播传输
/// - Relay ([RelayTransport]): HTTP 房间 + WebSocket
abstract class Transport {
  /// 本节点身份（创建时随机生成或持久化）
  String get myNodeId;

  /// 本节点在当前房间中的角色（由应用层通过 [setRole] 声明）
  ///
  /// **为什么不在 Transport 层协商角色**：角色是业务概念（房主 vs 加入者、
  /// 先手 vs 后手、白方 vs 黑方），不同应用规则不同。Transport 只负责通信，
  /// 角色由应用层基于其业务规则声明。
  NodeRole get myRole;

  /// 设置本节点角色。Discovery widget 完成 HTTP 握手后由业务层调用。
  void setRole(NodeRole role);

  /// 已确认的对端 nodeId（HTTP 握手后由 Discovery widget 设置）
  String? get peerNodeId;

  /// 设置对端 nodeId。Discovery widget 完成握手后调用。
  void setPeerNodeId(String? nodeId);

  /// 对端的角色（业务层可推断后设置）
  NodeRole get peerRole;

  /// 设置对端角色
  void setPeerRole(NodeRole role);

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

  /// 通过事件总线向所有同 scope 节点发送一条事件（topic 驱动）
  Future<void> sendEvent(String scope, String topic, Map<String, dynamic> data);

  /// 主动发布事件到 events 流（仅本地，不广播）
  void emit(TransportEvent event);

  /// 启动传输
  Future<void> start();

  /// 停止传输
  Future<void> stop();
}

/// scope 内的最终一致状态 — 纯数据容器，不承担身份/角色语义
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

  /// 收到对端变更（合并，不覆盖本地已有字段）
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