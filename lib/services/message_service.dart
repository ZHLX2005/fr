import '../models/models.dart';
import '../utils/storage_helper.dart';

class MessageService {
  static Future<List<Message>> getAllMessages() async {
    final messagesJson = await StorageHelper.getMessages();
    return messagesJson.map((json) => Message.fromJson(json)).toList();
  }

  static Future<List<Message>> getMessagesBetweenUsers(
    String userId1,
    String userId2,
  ) async {
    final allMessages = await getAllMessages();
    return allMessages
        .where(
          (m) =>
              (m.senderId == userId1 && m.receiverId == userId2) ||
              (m.senderId == userId2 && m.receiverId == userId1),
        )
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  static Future<void> sendMessage(Message message) async {
    final messages = await getAllMessages();
    messages.add(message);
    await StorageHelper.saveMessages(messages.map((m) => m.toJson()).toList());
  }

  static Future<void> updateMessageStatus(
    String messageId,
    MessageStatus status,
  ) async {
    final messages = await getAllMessages();
    final index = messages.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      messages[index] = messages[index].copyWith(status: status);
      await StorageHelper.saveMessages(
        messages.map((m) => m.toJson()).toList(),
      );
    }
  }

  static Future<void> markMessagesAsRead(
    String senderId,
    String receiverId,
  ) async {
    final messages = await getAllMessages();
    for (var i = 0; i < messages.length; i++) {
      if (messages[i].senderId == senderId &&
          messages[i].receiverId == receiverId &&
          !messages[i].isRead) {
        messages[i] = messages[i].copyWith(
          status: MessageStatus.read,
          readAt: DateTime.now(),
        );
      }
    }
    await StorageHelper.saveMessages(messages.map((m) => m.toJson()).toList());
  }

  static Future<void> deleteMessage(String messageId) async {
    final messages = await getAllMessages();
    messages.removeWhere((m) => m.id == messageId);
    await StorageHelper.saveMessages(messages.map((m) => m.toJson()).toList());
  }
}
