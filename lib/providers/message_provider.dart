import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../services/services.dart';

class MessageProvider with ChangeNotifier {
  List<Message> _messages = [];
  Map<String, List<Message>> _chatMessages = {};
  bool _isLoading = false;

  List<Message> get messages => _messages;
  bool get isLoading => _isLoading;

  List<Message> getChatMessages(String friendId) {
    return _chatMessages[friendId] ?? [];
  }

  Future<void> loadChatMessages(String currentUserId, String friendId) async {
    _isLoading = true;
    notifyListeners();

    final chatMessages =
        await MessageService.getMessagesBetweenUsers(currentUserId, friendId);
    _chatMessages[friendId] = chatMessages;

    _isLoading = false;
    notifyListeners();
  }

  Future<void> sendMessage({
    required String senderId,
    required String receiverId,
    required String content,
    MessageType type = MessageType.text,
  }) async {
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
    if (_chatMessages[receiverId] == null) {
      _chatMessages[receiverId] = [];
    }
    _chatMessages[receiverId]!.add(message);
    notifyListeners();

    // Simulate sending
    await Future.delayed(const Duration(milliseconds: 500));

    // Update to sent status
    final sentMessage = message.copyWith(status: MessageStatus.sent);
    await MessageService.sendMessage(sentMessage);

    // Update local list
    final index = _chatMessages[receiverId]!.indexWhere((m) => m.id == message.id);
    if (index != -1) {
      _chatMessages[receiverId]![index] = sentMessage;
    }

    // Update session
    await ChatSessionService.updateSessionWithMessage(senderId, sentMessage);
    if (senderId != receiverId) {
      await ChatSessionService.updateSessionWithMessage(receiverId, sentMessage);
    }

    notifyListeners();
  }

  Future<void> markAsRead(String senderId, String receiverId) async {
    await MessageService.markMessagesAsRead(senderId, receiverId);

    // Update local messages
    final friendId = senderId;
    if (_chatMessages[friendId] != null) {
      for (var i = 0; i < _chatMessages[friendId]!.length; i++) {
        if (_chatMessages[friendId]![i].senderId == senderId &&
            _chatMessages[friendId]![i].receiverId == receiverId &&
            !_chatMessages[friendId]![i].isRead) {
          _chatMessages[friendId]![i] = _chatMessages[friendId]![i].copyWith(
            status: MessageStatus.read,
            readAt: DateTime.now(),
          );
        }
      }
    }

    notifyListeners();
  }

  Future<void> refreshMessages(String currentUserId, String friendId) async {
    await loadChatMessages(currentUserId, friendId);
  }
}
