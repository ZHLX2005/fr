/// 传输事件 — 传输层事件总线原语
///
/// 业务层通过订阅 [Transport.events] 过滤感兴趣的事件。
class TransportEvent {
  const TransportEvent({
    required this.topic,
    required this.data,
    required this.timestamp,
  });

  /// 事件主题 — 业务层过滤维度
  final String topic;

  /// 事件载荷
  final Map<String, dynamic> data;

  /// 时间戳
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