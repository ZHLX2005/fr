import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class StorageHelper {
  static const String _usersKey = 'users';
  static const String _messagesKey = 'messages';
  static const String _friendsKey = 'friends';
  static const String _sessionsKey = 'sessions';
  static const String _currentUserKey = 'current_user';

  static Future<SharedPreferences> get _prefs async =>
      SharedPreferences.getInstance();

  static Future<void> setString(String key, String value) async {
    final prefs = await _prefs;
    await prefs.setString(key, value);
  }

  static Future<String?> getString(String key) async {
    final prefs = await _prefs;
    return prefs.getString(key);
  }

  static Future<void> setList(String key, List<dynamic> list) async {
    await setString(key, jsonEncode(list));
  }

  static Future<List<dynamic>> getList(String key) async {
    final value = await getString(key);
    if (value == null) return [];
    return jsonDecode(value);
  }

  // Users
  static Future<void> saveUsers(List<Map<String, dynamic>> users) async {
    await setList(_usersKey, users);
  }

  static Future<List<Map<String, dynamic>>> getUsers() async {
    return (await getList(_usersKey)).cast<Map<String, dynamic>>();
  }

  // Messages
  static Future<void> saveMessages(List<Map<String, dynamic>> messages) async {
    await setList(_messagesKey, messages);
  }

  static Future<List<Map<String, dynamic>>> getMessages() async {
    return (await getList(_messagesKey)).cast<Map<String, dynamic>>();
  }

  // Friends
  static Future<void> saveFriends(List<Map<String, dynamic>> friends) async {
    await setList(_friendsKey, friends);
  }

  static Future<List<Map<String, dynamic>>> getFriends() async {
    return (await getList(_friendsKey)).cast<Map<String, dynamic>>();
  }

  // Sessions
  static Future<void> saveSessions(List<Map<String, dynamic>> sessions) async {
    await setList(_sessionsKey, sessions);
  }

  static Future<List<Map<String, dynamic>>> getSessions() async {
    return (await getList(_sessionsKey)).cast<Map<String, dynamic>>();
  }

  // Current User
  static Future<void> setCurrentUser(String userId) async {
    final prefs = await _prefs;
    await prefs.setString(_currentUserKey, userId);
  }

  static Future<String?> getCurrentUser() async {
    final prefs = await _prefs;
    return prefs.getString(_currentUserKey);
  }

  static Future<void> clear() async {
    final prefs = await _prefs;
    await prefs.clear();
  }
}
