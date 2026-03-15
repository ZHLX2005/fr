import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/services.dart';

class ChatSessionProvider with ChangeNotifier {
  List<ChatSession> _sessions = [];
  bool _isLoading = false;

  List<ChatSession> get sessions => _sessions;
  bool get isLoading => _isLoading;

  int get totalUnreadCount {
    return _sessions.fold(0, (sum, s) => sum + s.unreadCount);
  }

  Future<void> init(String userId) async {
    _isLoading = true;
    notifyListeners();

    await refreshSessions(userId);

    _isLoading = false;
    notifyListeners();
  }

  Future<void> refreshSessions(String userId) async {
    _sessions = await ChatSessionService.getSessionsByUserId(userId);
    notifyListeners();
  }

  Future<void> markAsRead(String sessionId) async {
    await ChatSessionService.markSessionAsRead(sessionId);

    final index = _sessions.indexWhere((s) => s.id == sessionId);
    if (index != -1) {
      _sessions[index] = _sessions[index].copyWith(unreadCount: 0);
    }
    notifyListeners();
  }

  Future<void> deleteSession(String sessionId) async {
    await ChatSessionService.deleteSession(sessionId);
    _sessions.removeWhere((s) => s.id == sessionId);
    notifyListeners();
  }

  ChatSession? getSessionByFriendId(String userId, String friendId) {
    try {
      return _sessions.firstWhere((s) => s.friendId == friendId);
    } catch (e) {
      return null;
    }
  }

  Future<void> updateWithMessage(String userId, Message message) async {
    await ChatSessionService.updateSessionWithMessage(userId, message);
    await refreshSessions(userId);
  }
}
