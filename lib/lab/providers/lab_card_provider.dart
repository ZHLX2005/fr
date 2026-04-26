import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LabCardProvider with ChangeNotifier {
  static const String _storageKey = 'lab_card_backgrounds';
  static const String _favoritesKey = 'lab_card_favorites';
  static const String _favoritesOrderKey = 'lab_card_favorites_order';
  static LabCardProvider? _instance;

  factory LabCardProvider() {
    _instance ??= LabCardProvider._internal();
    return _instance!;
  }

  LabCardProvider._internal() : _isLoaded = false {
    _loadData();
  }

  bool _isLoaded;
  bool get isLoaded => _isLoaded;

  Future<void> get onLoaded async {
    while (!_isLoaded) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  final Map<String, String> _backgrounds = {};
  final Set<String> _favorites = <String>{};
  final List<String> _favoritesOrder = [];

  String? getBackground(String demoTitle) {
    return _backgrounds[demoTitle];
  }

  bool isFavorite(String demoTitle) {
    return _favorites.contains(demoTitle);
  }

  List<String> getFavorites() {
    return _favorites.toList()..sort();
  }

  List<String> getFavoritesOrder() {
    if (_favoritesOrder.isEmpty) {
      return _favorites.toList()..sort();
    }
    return List<String>.from(_favoritesOrder);
  }

  bool isLocalFile(String demoTitle) {
    final path = _backgrounds[demoTitle];
    if (path == null) return false;
    return path.startsWith('/') || path.contains('applicationDocuments');
  }

  Future<void> setBackground(String demoTitle, String? imageUrl) async {
    if (imageUrl == null || imageUrl.isEmpty) {
      _backgrounds.remove(demoTitle);
    } else {
      _backgrounds[demoTitle] = imageUrl;
    }
    await _saveBackgrounds();
    notifyListeners();
  }

  Future<void> removeBackground(String demoTitle) async {
    _backgrounds.remove(demoTitle);
    await _saveBackgrounds();
    notifyListeners();
  }

  Future<void> setFavorite(String demoTitle, bool value) async {
    if (value) {
      _favorites.add(demoTitle);
    } else {
      _favorites.remove(demoTitle);
    }
    await _saveFavorites();
    await syncFavoritesOrder();
    notifyListeners();
  }

  Future<void> reorderFavorites(List<String> ordered) async {
    _favoritesOrder
      ..clear()
      ..addAll(ordered);
    await _saveFavoritesOrder();
    notifyListeners();
  }

  Future<void> syncFavoritesOrder() async {
    _favoritesOrder.removeWhere((title) => !_favorites.contains(title));
    await _saveFavoritesOrder();
  }

  Future<void> clearAll() async {
    _backgrounds.clear();
    _favorites.clear();
    await _saveBackgrounds();
    await _saveFavorites();
    notifyListeners();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_storageKey);
    final favorites = prefs.getStringList(_favoritesKey);

    if (data != null && data.isNotEmpty) {
      try {
        final Map<String, dynamic> json = {};
        final pairs = data.split(',');
        for (final pair in pairs) {
          final parts = pair.split(':');
          if (parts.length == 2) {
            json[parts[0]] = parts[1];
          }
        }
        _backgrounds
          ..clear()
          ..addAll(json.map((key, value) => MapEntry(key, value as String)));
      } catch (e) {
        if (kDebugMode) {
          print('Failed to load lab card backgrounds: $e');
        }
      }
    }

    _favorites
      ..clear()
      ..addAll(favorites ?? const <String>[]);

    final favoritesOrder = prefs.getStringList(_favoritesOrderKey);
    _favoritesOrder
      ..clear()
      ..addAll(favoritesOrder ?? <String>[]);

    _isLoaded = true;
  }

  Future<void> _saveBackgrounds() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _backgrounds.entries
        .map((e) => '${e.key}:${e.value}')
        .join(',');
    await prefs.setString(_storageKey, data);
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoritesKey, getFavorites());
  }

  Future<void> _saveFavoritesOrder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoritesOrderKey, _favoritesOrder);
  }

  static const List<String> presetImages = [
    'https://picsum.photos/seed/demo1/400/300',
    'https://picsum.photos/seed/demo2/400/300',
    'https://picsum.photos/seed/demo3/400/300',
    'https://picsum.photos/seed/demo4/400/300',
    'https://picsum.photos/seed/nature1/400/300',
    'https://picsum.photos/seed/nature2/400/300',
    'https://picsum.photos/seed/tech1/400/300',
    'https://picsum.photos/seed/tech2/400/300',
    'https://picsum.photos/seed/art1/400/300',
    'https://picsum.photos/seed/art2/400/300',
  ];
}
