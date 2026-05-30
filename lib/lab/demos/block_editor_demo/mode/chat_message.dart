class ChatMessage {
  final String content;
  final bool isMe;
  final DateTime createdAt;

  ChatMessage({
    required this.content,
    required this.isMe,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}
