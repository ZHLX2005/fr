import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lab 卡片背景图片管理器
/// 负责管理每个 demo 卡片的背景图片配置
class LabCardProvider with ChangeNotifier {
  static const String _storageKey = 'lab_card_backgrounds';
  static LabCardProvider? _instance;

  factory LabCardProvider() {
    _instance ??= LabCardProvider._internal();
    return _instance!;
  }

  LabCardProvider._internal() : _isLoaded = false {
    _loadBackgrounds();
  }

  /// 数据是否已从持久化加载完成
  bool _isLoaded;
  bool get isLoaded => _isLoaded;

  /// 数据加载完成后触发（用于外部 await）
  Future<void> get onLoaded async {
    while (!_isLoaded) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  // 存储 demo 标题 -> 背景图片 URL 的映射
  final Map<String, String> _backgrounds = {};

  /// 获取指定卡片的背景图片 URL 或本地路径
  String? getBackground(String demoTitle) {
    return _backgrounds[demoTitle];
  }

  /// 判断背景是否为本地文件
  bool isLocalFile(String demoTitle) {
    final path = _backgrounds[demoTitle];
    if (path == null) return false;
    // 本地文件路径通常以 / 开头或包含应用目录
    return path.startsWith('/') || path.contains('applicationDocuments');
  }

  /// 设置指定卡片的背景图片 URL
  Future<void> setBackground(String demoTitle, String? imageUrl) async {
    if (imageUrl == null || imageUrl.isEmpty) {
      _backgrounds.remove(demoTitle);
    } else {
      _backgrounds[demoTitle] = imageUrl;
    }
    await _saveBackgrounds();
    notifyListeners();
  }

  /// 移除指定卡片的背景图片
  Future<void> removeBackground(String demoTitle) async {
    _backgrounds.remove(demoTitle);
    await _saveBackgrounds();
    notifyListeners();
  }

  /// 清除所有背景图片
  Future<void> clearAll() async {
    _backgrounds.clear();
    await _saveBackgrounds();
    notifyListeners();
  }

  /// 从持久化存储加载背景配置
  Future<void> _loadBackgrounds() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_storageKey);
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
        _backgrounds.clear();
        json.forEach((key, value) {
          _backgrounds[key] = value as String;
        });
      } catch (e) {
        if (kDebugMode) {
          print('加载背景配置失败: $e');
        }
      }
    }
    _isLoaded = true;
  }

  /// 保存背景配置到持久化存储
  Future<void> _saveBackgrounds() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _backgrounds.entries
        .map((e) => '${e.key}:${e.value}')
        .join(',');
    await prefs.setString(_storageKey, data);
  }

  /// 预设的背景图片列表
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
