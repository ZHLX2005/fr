class LocalnetMessage {
  final String id;
  final String senderId;
  final String senderAlias;
  final String content;
  final DateTime timestamp;
  final MessageType type;

  LocalnetMessage({
    required this.id,
    required this.senderId,
    required this.senderAlias,
    required this.content,
    required this.timestamp,
    this.type = MessageType.text,
  });

  factory LocalnetMessage.fromJson(Map<String, dynamic> json) {
    return LocalnetMessage(
      id: json['id'] as String,
      senderId: json['senderId'] as String,
      senderAlias: json['senderAlias'] as String,
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      type: MessageType.values.firstWhere(
        (e) => e.name == (json['type'] as String?),
        orElse: () => MessageType.text,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'senderId': senderId,
    'senderAlias': senderAlias,
    'content': content,
    'timestamp': timestamp.toIso8601String(),
    'type': type.name,
  };
}

enum MessageType { text, file }
