// lib/core/game_kit/chat/chat_event.dart
//
// Unified in-game chat event (text from chatRing + emoji from emojiRing).

import '../emoji/emoji_overlay.dart' show SnapshotEmojiEvent, emojisFromSnapshot;

/// Message kind for avatar-anchored bubbles / history sheet.
enum ChatKind { text, emoji }

/// One chat event from snapshot rings (server-authoritative).
class ChatEvent {
  final String id;
  final ChatKind kind;
  final String from;
  final int seq;
  final int atMs;

  /// Plain text when [kind] == [ChatKind.text].
  final String? text;

  /// Sticker id when [kind] == [ChatKind.emoji].
  final String? emojiId;

  const ChatEvent({
    required this.id,
    required this.kind,
    required this.from,
    required this.seq,
    required this.atMs,
    this.text,
    this.emojiId,
  });

  bool get isText => kind == ChatKind.text;
  bool get isEmoji => kind == ChatKind.emoji;

  factory ChatEvent.textFromJson(Map<String, dynamic> j) {
    final seq = (j['seq'] as num?)?.toInt() ?? 0;
    final text = (j['text'] ?? j['msg'] ?? '').toString();
    return ChatEvent(
      id: (j['id'] ?? 'c$seq').toString(),
      kind: ChatKind.text,
      from: (j['from'] ?? j['device_id'] ?? '').toString(),
      seq: seq,
      atMs: (j['at'] as num?)?.toInt() ??
          (j['ts'] as num?)?.toInt() ??
          0,
      text: text,
    );
  }

  factory ChatEvent.fromEmoji(SnapshotEmojiEvent e) => ChatEvent(
        id: e.id.isNotEmpty ? e.id : 'e${e.seq}',
        kind: ChatKind.emoji,
        from: e.from,
        seq: e.seq,
        atMs: e.atMs,
        emojiId: e.emojiId,
      );
}

/// Read `chatRing` (and aliases) from snapshot context.
List<ChatEvent> chatTextsFromSnapshot(Map<String, dynamic> ctx) {
  for (final key in ['chatRing', 'chats', 'chat_events']) {
    final raw = ctx[key];
    if (raw is! List || raw.isEmpty) continue;
    final out = <ChatEvent>[];
    for (final item in raw) {
      if (item is! Map) continue;
      try {
        final e = ChatEvent.textFromJson(Map<String, dynamic>.from(item));
        if (e.text == null || e.text!.isEmpty) continue;
        out.add(e);
      } catch (_) {}
    }
    if (out.isNotEmpty) return out;
  }
  return const [];
}

/// Merge emojiRing + chatRing, sorted by time then seq (stable history).
List<ChatEvent> mergedChatEventsFromSnapshot(Map<String, dynamic> ctx) {
  final texts = chatTextsFromSnapshot(ctx);
  final emojis = emojisFromSnapshot(ctx).map(ChatEvent.fromEmoji);
  final all = <ChatEvent>[...texts, ...emojis];
  all.sort((a, b) {
    final t = a.atMs.compareTo(b.atMs);
    if (t != 0) return t;
    // Prefer stable order: emoji vs text with same ts — use kind then id
    final s = a.seq.compareTo(b.seq);
    if (s != 0) return s;
    return a.id.compareTo(b.id);
  });
  return all;
}
