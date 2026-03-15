import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/services.dart';

class UserProvider with ChangeNotifier {
  User? _currentUser;
  List<User> _users = [];
  bool _isLoading = false;

  User? get currentUser => _currentUser;
  List<User> get users => _users;
  bool get isLoading => _isLoading;

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    await MockDataService.generateTestData();
    _users = await UserService.getAllUsers();
    _currentUser = await UserService.getCurrentUser();

    _isLoading = false;
    // Delay notifyListeners to avoid calling during build
    Future.microtask(() => notifyListeners());
  }

  Future<void> refreshUsers() async {
    _users = await UserService.getAllUsers();
    notifyListeners();
  }

  Future<void> updateProfile({
    String? nickname,
    String? avatar,
    String? signature,
    String? status,
  }) async {
    if (_currentUser == null) return;

    _currentUser = _currentUser!.copyWith(
      nickname: nickname ?? _currentUser!.nickname,
      avatar: avatar ?? _currentUser!.avatar,
      signature: signature ?? _currentUser!.signature,
      status: status ?? _currentUser!.status,
    );

    await UserService.updateUser(_currentUser!);
    await refreshUsers();
    notifyListeners();
  }

  Future<void> setStatus(String status) async {
    if (_currentUser == null) return;
    await updateProfile(status: status);
  }

  User? getUserById(String id) {
    try {
      return _users.firstWhere((u) => u.id == id);
    } catch (e) {
      return null;
    }
  }
}
