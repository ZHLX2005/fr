// lib/core/game_kit/emoji/emoji_snapshot.dart
//
// 快照 emoji 事件模型与解析（纯逻辑，无 UI）。
// UI 呈现在 lib/core/ui/game/emoji_overlay.dart；本文件供 chat_event /
// emoji_overlay 双方消费，避免「逻辑 import UI」的反向依赖。

/// 快照中的单条 emoji 事件（服务端权威）。
class SnapshotEmojiEvent {
  final String id;
  final String emojiId;
  final String from;
  final int seq;
  final int atMs;

  const SnapshotEmojiEvent({
    required this.id,
    required this.emojiId,
    required this.from,
    required this.seq,
    required this.atMs,
  });

  factory SnapshotEmojiEvent.fromJson(Map<String, dynamic> j) =>
      SnapshotEmojiEvent(
        id: (j['id'] ?? j['emoji_id'] ?? j['emojiId'] ?? j['seq']).toString(),
        emojiId: (j['emoji_id'] ?? j['emojiId'] ?? j['id'] ?? j['emoji'] ?? '')
            .toString(),
        from: (j['from'] ?? j['device_id'] ?? '').toString(),
        seq: (j['seq'] as num?)?.toInt() ?? 0,
        atMs: (j['at'] as num?)?.toInt() ??
            (j['ts'] as num?)?.toInt() ??
            0,
      );
}

/// 从快照 context 读取 emojis 列表（兼容多种字段名）。
List<SnapshotEmojiEvent> emojisFromSnapshot(Map<String, dynamic> ctx) {
  final candidates = <String>[
    'emojiRing',
    'emojis',
    'emoji_events',
    'recent_emojis',
  ];
  for (final key in candidates) {
    final raw = ctx[key];
    if (raw is List && raw.isNotEmpty) {
      final out = <SnapshotEmojiEvent>[];
      for (final item in raw) {
        if (item is! Map) continue;
        try {
          final e = SnapshotEmojiEvent.fromJson(Map<String, dynamic>.from(item));
          if (e.emojiId.isEmpty) continue;
          out.add(e);
        } catch (_) {}
      }
      if (out.isNotEmpty) return out;
    }
  }
  return const [];
}
