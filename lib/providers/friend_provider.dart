import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/services.dart';

class FriendProvider with ChangeNotifier {
  List<Friend> _friends = [];
  List<FriendRequest> _pendingRequests = [];
  bool _isLoading = false;
  String _searchQuery = '';

  List<Friend> get friends {
    if (_searchQuery.isEmpty) return _friends;
    return _friends
        .where((f) =>
            f.user.nickname.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            (f.remark?.toLowerCase().contains(_searchQuery.toLowerCase()) ??
                false))
        .toList();
  }

  List<Friend> get onlineFriends =>
      _friends.where((f) => f.user.status == 'online').toList();

  List<FriendRequest> get pendingRequests => _pendingRequests;
  bool get isLoading => _isLoading;

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    _friends = await FriendService.getAcceptedFriends();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> refreshFriends() async {
    _friends = await FriendService.getAcceptedFriends();
    notifyListeners();
  }

  Future<void> sendFriendRequest(String userId, String message) async {
    // In a real app, this would send to a backend
    // For now, we'll just create a pending request
    final request = FriendRequest(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fromUserId: (await UserService.getCurrentUserId())!,
      toUserId: userId,
      message: message,
      createdAt: DateTime.now(),
    );
    notifyListeners();
  }

  Future<void> acceptFriendRequest(String requestId) async {
    _pendingRequests.removeWhere((r) => r.id == requestId);
    notifyListeners();
  }

  Future<void> rejectFriendRequest(String requestId) async {
    _pendingRequests.removeWhere((r) => r.id == requestId);
    notifyListeners();
  }

  Future<void> removeFriend(String friendId) async {
    await FriendService.removeFriend(friendId);
    _friends.removeWhere((f) => f.id == friendId);
    notifyListeners();
  }

  Future<void> updateRemark(String friendId, String remark) async {
    await FriendService.updateFriendRemark(friendId, remark);
    await refreshFriends();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  Friend? getFriendByUserId(String userId) {
    try {
      return _friends.firstWhere((f) => f.user.id == userId);
    } catch (e) {
      return null;
    }
  }

  List<Friend> getFriendsByStatus(String status) {
    return _friends.where((f) => f.user.status == status).toList();
  }
}
