import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../utils/storage_helper.dart';

class ChatSessionService {
  static const Uuid _uuid = Uuid();

  static Future<List<ChatSession>> getAllSessions() async {
    final sessionsJson = await StorageHelper.getSessions();
    return sessionsJson.map((json) => ChatSession.fromJson(json)).toList();
  }

  static Future<List<ChatSession>> getSessionsByUserId(String userId) async {
    final sessions = await getAllSessions();
    return sessions.where((s) => s.userId == userId).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  static Future<ChatSession?> getSessionByFriendId(
      String userId, String friendId) async {
    final sessions = await getSessionsByUserId(userId);
    try {
      return sessions.firstWhere((s) => s.friendId == friendId);
    } catch (e) {
      return null;
    }
  }

  static Future<void> createOrUpdateSession(ChatSession session) async {
    final sessions = await getAllSessions();
    final index = sessions.indexWhere((s) => s.id == session.id);
    if (index != -1) {
      sessions[index] = session;
    } else {
      sessions.add(session);
    }
    await StorageHelper.saveSessions(sessions.map((s) => s.toJson()).toList());
  }

  static Future<void> updateSessionWithMessage(
      String userId, Message message) async {
    final friendId = message.senderId == userId
        ? message.receiverId
        : message.senderId;
    var session = await getSessionByFriendId(userId, friendId);

    if (session == null) {
      session = ChatSession(
        id: _uuid.v4(),
        userId: userId,
        friendId: friendId,
        lastMessage: message,
        unreadCount: message.senderId != userId ? 1 : 0,
        updatedAt: message.createdAt,
      );
    } else {
      final newUnreadCount = message.senderId != userId
          ? session.unreadCount + 1
          : session.unreadCount;
      session = session.copyWith(
        lastMessage: message,
        unreadCount: newUnreadCount,
        updatedAt: message.createdAt,
      );
    }

    await createOrUpdateSession(session!);
  }

  static Future<void> markSessionAsRead(String sessionId) async {
    final sessions = await getAllSessions();
    final index = sessions.indexWhere((s) => s.id == sessionId);
    if (index != -1) {
      sessions[index] = sessions[index].copyWith(unreadCount: 0);
      await StorageHelper.saveSessions(sessions.map((s) => s.toJson()).toList());
    }
  }

  static Future<void> deleteSession(String sessionId) async {
    final sessions = await getAllSessions();
    sessions.removeWhere((s) => s.id == sessionId);
    await StorageHelper.saveSessions(sessions.map((s) => s.toJson()).toList());
  }

  static Future<int> getTotalUnreadCount(String userId) async {
    final sessions = await getSessionsByUserId(userId);
    return sessions.fold<int>(0, (sum, s) => sum + s.unreadCount);
  }
}
