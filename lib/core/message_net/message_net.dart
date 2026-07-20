import 'dart:async';
import 'dart:convert';

import 'lan_message_net.dart';
import 'relay_message_net.dart';

/// 传输模式
enum MessageNetMode {
  /// 局域网：UDP 多播（同一子网内所有节点）
  lan,

  /// 互联网：HTTP 房间号 + WebSocket 帧
  relay,
}

/// 日志条目 — 业务载荷的统一表示
///
/// 每条日志全广播到所有在场节点。Raft 风格最终一致：
/// 节点收到日志后按 topic 分发，业务层自己解释 `data` 字段。
class LogEntry {
  LogEntry({
    required this.from,
    required this.topic,
    required this.data,
    required this.timestamp,
  });

  /// 发送方节点 id
  final String from;

  /// 业务主题 — 用于订阅分片
  final String topic;

  /// 业务载荷
  final Map<String, dynamic> data;

  /// 时间戳
  final DateTime timestamp;

  /// 序列化为 wire 格式（JSON）
  String encode() => jsonEncode({
        'from': from,
        'topic': topic,
        'data': data,
        'ts': timestamp.toIso8601String(),
      });

  /// 从 wire 格式反序列化
  static LogEntry decode(String wire) {
    final json = jsonDecode(wire) as Map<String, dynamic>;
    return LogEntry(
      from: json['from'] as String? ?? 'unknown',
      topic: json['topic'] as String? ?? '',
      data: (json['data'] as Map?)?.cast<String, dynamic>() ?? const {},
      timestamp: DateTime.tryParse(json['ts'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// MessageNet — 全广播日志同步层（独立模块）
///
/// ## 设计哲学
///
/// - **零元数据**：连接只关心"能不能连上"，业务身份信息（myId/alias）作为日志字段随每条消息传递
/// - **零抽象**：`MessageNet` 是抽象类，子类（LAN/Relay）隐藏实现细节
/// - **队列积压**：`append()` 立即入队，连接建立后批量推送；连接断开时本地可继续 append
/// - **数据驱动**：业务层订阅 topic 拿到日志，自己解释 data 字段
///
/// ## 两种模式
///
/// - **LAN**：UDP 多播（同子网内所有节点）
/// - **Relay**：HTTP 房间号 + WebSocket（跨网络，需中继服务器）
abstract class MessageNet {
  MessageNet._();

  /// 启动网络（工厂方法）
  ///
  /// LAN 模式：启动 UDP 多播监听
  /// Relay 模式：需先调用 [createRoom] 或 [joinRoom] 才能 append
  static Future<MessageNet> start({
    required MessageNetMode mode,
    String? relayUrl,
    int multicastPort = 5678,
    String multicastAddress = '239.255.255.255',
  }) async {
    switch (mode) {
      case MessageNetMode.lan:
        return await LanMessageNet.create(
          multicastPort: multicastPort,
          multicastAddress: multicastAddress,
        );
      case MessageNetMode.relay:
        if (relayUrl == null || relayUrl.isEmpty) {
          throw ArgumentError('relay 模式必须提供 relayUrl');
        }
        return await RelayMessageNet.create(relayUrl: relayUrl);
    }
  }

  /// 释放资源
  Future<void> stop();

  /// 当前房间号（relay 模式才有）
  String? get roomCode;

  /// 追加一条日志（立即入队，连接可用后批量推送）
  void append(LogEntry entry);

  /// 订阅某 topic 的日志
  Stream<LogEntry> watch(String topic);

  /// 订阅所有日志
  Stream<LogEntry> get onAny;

  /// Relay 模式：创建房间
  /// LAN 模式：无操作，返回 null
  Future<String?> createRoom();

  /// Relay 模式：加入房间
  /// LAN 模式：无操作
  Future<void> joinRoom(String code);

  /// Relay 模式：离开房间
  /// LAN 模式：无操作
  void leaveRoom();
}