// lib/core/localnet_biz/localnet_message.dart
//
// 通用消息模型 — 业务层传到 room topic 后由各端按 fromNodeId 过滤
// 与具体业务（聊天/发牌/文件）解耦。

class LocalnetMessage {
  final String id;
  final String fromNodeId;
  final String fromAlias;
  final String text;
  final DateTime ts;
  final Map<String, dynamic>? extra;

  LocalnetMessage({
    required this.id,
    required this.fromNodeId,
    required this.fromAlias,
    required this.text,
    required this.ts,
    this.extra,
  });

  Map<String, dynamic> toTransportPayload() => {
        'type': 'message',
        'id': id,
        'from': fromNodeId,
        'fromAlias': fromAlias,
        'text': text,
        'ts': ts.toIso8601String(),
        if (extra != null) ...extra!,
      };

  factory LocalnetMessage.fromTransportEvent(Map<String, dynamic> payload) {
    return LocalnetMessage(
      id: (payload['id'] as String?) ?? '',
      fromNodeId: (payload['from'] as String?) ?? '',
      fromAlias: (payload['fromAlias'] as String?) ?? '',
      text: (payload['text'] as String?) ?? '',
      ts: DateTime.tryParse(payload['ts'] as String? ?? '') ?? DateTime.now(),
      extra: payload['extra'] is Map
          ? Map<String, dynamic>.from(payload['extra'] as Map)
          : null,
    );
  }
}
