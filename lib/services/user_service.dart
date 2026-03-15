import '../models/models.dart';
import '../utils/storage_helper.dart';

class UserService {
  static Future<List<User>> getAllUsers() async {
    final usersJson = await StorageHelper.getUsers();
    return usersJson.map((json) => User.fromJson(json)).toList();
  }

  static Future<User?> getUserById(String id) async {
    final users = await getAllUsers();
    try {
      return users.firstWhere((user) => user.id == id);
    } catch (e) {
      return null;
    }
  }

  static Future<void> createUser(User user) async {
    final users = await getAllUsers();
    users.add(user);
    await StorageHelper.saveUsers(users.map((u) => u.toJson()).toList());
  }

  static Future<void> updateUser(User updatedUser) async {
    final users = await getAllUsers();
    final index = users.indexWhere((u) => u.id == updatedUser.id);
    if (index != -1) {
      users[index] = updatedUser;
      await StorageHelper.saveUsers(users.map((u) => u.toJson()).toList());
    }
  }

  static Future<void> deleteUser(String id) async {
    final users = await getAllUsers();
    users.removeWhere((u) => u.id == id);
    await StorageHelper.saveUsers(users.map((u) => u.toJson()).toList());
  }

  static Future<String?> getCurrentUserId() async {
    return await StorageHelper.getCurrentUser();
  }

  static Future<User?> getCurrentUser() async {
    final id = await getCurrentUserId();
    if (id == null) return null;
    return await getUserById(id);
  }

  static Future<void> setCurrentUser(String id) async {
    await StorageHelper.setCurrentUser(id);
  }
}
