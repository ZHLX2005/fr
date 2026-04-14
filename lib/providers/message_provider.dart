import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../services/services.dart';

class MessageProvider with ChangeNotifier {
  List<Message> _messages = [];
  Map<String, List<Message>> _chatMessages = {};

  List<Message> get messages => _messages;

  List<Message> getChatMessages(String currentUserId, String friendId) {
    // 使用统一的聊天key
    final chatKey = [currentUserId, friendId]..sort();
    final conversationId = '${chatKey[0]}_${chatKey[1]}';
    return _chatMessages[conversationId] ?? [];
  }

  Future<void> loadChatMessages(String currentUserId, String friendId) async {
    // 使用统一的聊天key
    final chatKey = [currentUserId, friendId]..sort();
    final conversationId = '${chatKey[0]}_${chatKey[1]}';

    final chatMessages = await MessageService.getMessagesBetweenUsers(
      currentUserId,
      friendId,
    );
    _chatMessages[conversationId] = chatMessages;

    notifyListeners();
  }

  Future<void> sendMessage({
    required String senderId,
    required String receiverId,
    required String content,
    MessageType type = MessageType.text,
  }) async {
    // 创建统一的聊天key（使用较小的ID作为key，确保同一对话使用同一个key）
    final chatKey = [senderId, receiverId]..sort();
    final conversationId = '${chatKey[0]}_${chatKey[1]}';

    try {
      final message = Message(
        id: const Uuid().v4(),
        senderId: senderId,
        receiverId: receiverId,
        content: content,
        type: type,
        status: MessageStatus.sending,
        createdAt: DateTime.now(),
      );

      // Add to local list immediately
      if (_chatMessages[conversationId] == null) {
        _chatMessages[conversationId] = [];
      }
      _chatMessages[conversationId]!.add(message);
      notifyListeners();

      // Simulate sending
      await Future.delayed(const Duration(milliseconds: 300));

      // Update to sent status
      final sentMessage = message.copyWith(status: MessageStatus.sent);
      await MessageService.sendMessage(sentMessage);

      // Update local list
      final index = _chatMessages[conversationId]!.indexWhere(
        (m) => m.id == message.id,
      );
      if (index != -1) {
        _chatMessages[conversationId]![index] = sentMessage;
      }

      notifyListeners();

      // Update session
      await ChatSessionService.updateSessionWithMessage(senderId, sentMessage);
      if (senderId != receiverId) {
        await ChatSessionService.updateSessionWithMessage(
          receiverId,
          sentMessage,
        );
      }
    } catch (e) {
      debugPrint('Send message error: $e');
    }
  }

  Future<void> markAsRead(String senderId, String receiverId) async {
    await MessageService.markMessagesAsRead(senderId, receiverId);

    // 使用统一的聊天key
    final chatKey = [senderId, receiverId]..sort();
    final conversationId = '${chatKey[0]}_${chatKey[1]}';

    // Update local messages
    if (_chatMessages[conversationId] != null) {
      for (var i = 0; i < _chatMessages[conversationId]!.length; i++) {
        if (_chatMessages[conversationId]![i].senderId == senderId &&
            _chatMessages[conversationId]![i].receiverId == receiverId &&
            !_chatMessages[conversationId]![i].isRead) {
          _chatMessages[conversationId]![i] = _chatMessages[conversationId]![i]
              .copyWith(status: MessageStatus.read, readAt: DateTime.now());
        }
      }
    }

    notifyListeners();
  }

  Future<void> refreshMessages(String currentUserId, String friendId) async {
    await loadChatMessages(currentUserId, friendId);
  }
}
