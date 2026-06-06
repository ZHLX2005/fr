/// 单条 AI 对话消息
class AIChatMessage {
  final String id;
  final bool isUser;
  final String content;
  final DateTime createdAt;
  final bool isLoading;

  AIChatMessage({
    required this.id,
    required this.isUser,
    required this.content,
    DateTime? createdAt,
    this.isLoading = false,
  }) : createdAt = createdAt ?? DateTime.now();

  factory AIChatMessage.user(String content) => AIChatMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        isUser: true,
        content: content,
      );

  factory AIChatMessage.ai(String content) => AIChatMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        isUser: false,
        content: content,
      );

  factory AIChatMessage.loading() => AIChatMessage(
        id: 'loading',
        isUser: false,
        content: '',
        isLoading: true,
      );

  AIChatMessage copyWith({
    String? id,
    bool? isUser,
    String? content,
    DateTime? createdAt,
    bool? isLoading,
  }) =>
      AIChatMessage(
        id: id ?? this.id,
        isUser: isUser ?? this.isUser,
        content: content ?? this.content,
        createdAt: createdAt ?? this.createdAt,
        isLoading: isLoading ?? this.isLoading,
      );
}

/// 与一个 Block 关联的 AI 对话
class BlockAIConversation {
  final String blockId;
  final List<AIChatMessage> _messages = [];

  BlockAIConversation({required this.blockId});

  List<AIChatMessage> get messages => List.unmodifiable(_messages);

  AIChatMessage? get lastBubble {
    for (int i = _messages.length - 1; i >= 0; i--) {
      if (!_messages[i].isUser && !_messages[i].isLoading) {
        return _messages[i];
      }
    }
    return null;
  }

  bool get hasConversation => _messages.isNotEmpty;

  bool get hasLoading => _messages.any((m) => m.isLoading);

  void addMessage(AIChatMessage msg) => _messages.add(msg);

  void removeLoading() {
    _messages.removeWhere((m) => m.isLoading);
  }

  /// 最新一条 AI 回复的文本内容（用于气泡显示）
  String get latestResponseText {
    final bubble = lastBubble;
    return bubble?.content ?? '';
  }

  /// 清空所有消息（用于点击对话时隐藏气泡）
  void clearBubble() => _messages.clear();
}
