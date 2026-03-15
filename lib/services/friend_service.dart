import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../utils/storage_helper.dart';

class FriendService {
  static const Uuid _uuid = Uuid();

  static Future<List<Friend>> getAllFriends() async {
    final friendsJson = await StorageHelper.getFriends();
    return friendsJson.map((json) => Friend.fromJson(json)).toList();
  }

  static Future<List<Friend>> getAcceptedFriends() async {
    final friends = await getAllFriends();
    return friends.where((f) => f.status == FriendStatus.accepted).toList();
  }

  static Future<Friend?> getFriendByUserId(String userId) async {
    final friends = await getAllFriends();
    try {
      return friends.firstWhere((f) => f.user.id == userId);
    } catch (e) {
      return null;
    }
  }

  static Future<void> addFriend(Friend friend) async {
    final friends = await getAllFriends();
    friends.add(friend);
    await StorageHelper.saveFriends(friends.map((f) => f.toJson()).toList());
  }

  static Future<void> removeFriend(String friendId) async {
    final friends = await getAllFriends();
    friends.removeWhere((f) => f.id == friendId);
    await StorageHelper.saveFriends(friends.map((f) => f.toJson()).toList());
  }

  static Future<void> updateFriendRemark(
      String friendId, String remark) async {
    final friends = await getAllFriends();
    final index = friends.indexWhere((f) => f.id == friendId);
    if (index != -1) {
      friends[index] = friends[index].copyWith(remark: remark);
      await StorageHelper.saveFriends(friends.map((f) => f.toJson()).toList());
    }
  }

  static Future<List<Friend>> searchFriends(String query) async {
    final friends = await getAcceptedFriends();
    if (query.isEmpty) return friends;
    return friends
        .where((f) =>
            f.user.nickname.toLowerCase().contains(query.toLowerCase()) ||
            (f.remark?.toLowerCase().contains(query.toLowerCase()) ?? false))
        .toList();
  }

  static Future<void> blockFriend(String friendId) async {
    final friends = await getAllFriends();
    final index = friends.indexWhere((f) => f.id == friendId);
    if (index != -1) {
      friends[index] = friends[index].copyWith(status: FriendStatus.blocked);
      await StorageHelper.saveFriends(friends.map((f) => f.toJson()).toList());
    }
  }

  static Future<void> unblockFriend(String friendId) async {
    final friends = await getAllFriends();
    final index = friends.indexWhere((f) => f.id == friendId);
    if (index != -1) {
      friends[index] = friends[index].copyWith(status: FriendStatus.accepted);
      await StorageHelper.saveFriends(friends.map((f) => f.toJson()).toList());
    }
  }
}
