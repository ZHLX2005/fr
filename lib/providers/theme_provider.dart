import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme/app_theme.dart';

/// 主题Provider
///
/// 管理应用主题状态，包括主题切换和持久化
class ThemeProvider extends ChangeNotifier {
  static const String _themeKey = 'app_theme_mode';

  AppThemeMode _themeMode = AppThemeMode.light;
  SharedPreferences? _prefs;

  /// 当前主题模式
  AppThemeMode get themeMode => _themeMode;

  /// 是否为深色模式
  bool get isDarkMode => _themeMode == AppThemeMode.dark;

  /// 当前主题数据
  ThemeData get themeData => AppTheme.getThemeData(_themeMode);

  /// 当前主题对应的Material主题模式
  ThemeMode get themeModeValue {
    switch (_themeMode) {
      case AppThemeMode.dark:
        return ThemeMode.dark;
      default:
        return ThemeMode.light;
    }
  }

  /// 初始化主题Provider
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadThemeMode();
  }

  /// 从本地存储加载主题模式
  Future<void> _loadThemeMode() async {
    if (_prefs == null) return;

    final savedTheme = _prefs!.getString(_themeKey);
    if (savedTheme != null) {
      try {
        _themeMode = AppThemeMode.values.firstWhere(
          (mode) => mode.name == savedTheme,
          orElse: () => AppThemeMode.light,
        );
      } catch (_) {
        _themeMode = AppThemeMode.light;
      }
    }
    notifyListeners();
  }

  /// 保存主题模式到本地存储
  Future<void> _saveThemeMode() async {
    if (_prefs == null) {
      _prefs = await SharedPreferences.getInstance();
    }
    await _prefs!.setString(_themeKey, _themeMode.name);
  }

  /// 设置主题模式
  ///
  /// [mode] 新的主题模式
  Future<void> setThemeMode(AppThemeMode mode) async {
    if (_themeMode == mode) return;

    _themeMode = mode;
    await _saveThemeMode();
    notifyListeners();
  }

  /// 切换到浅色主题
  Future<void> setLight() async {
    await setThemeMode(AppThemeMode.light);
  }

  /// 切换到深色主题
  Future<void> setDark() async {
    await setThemeMode(AppThemeMode.dark);
  }

  /// 切换到粉红色主题
  Future<void> setPink() async {
    await setThemeMode(AppThemeMode.pink);
  }

  /// 在浅色和深色之间切换
  Future<void> toggleTheme() async {
    final newMode = _themeMode == AppThemeMode.dark
        ? AppThemeMode.light
        : AppThemeMode.dark;
    await setThemeMode(newMode);
  }

  /// 获取下一个主题模式（用于循环切换）
  AppThemeMode get nextThemeMode {
    switch (_themeMode) {
      case AppThemeMode.light:
        return AppThemeMode.dark;
      case AppThemeMode.dark:
        return AppThemeMode.pink;
      case AppThemeMode.pink:
        return AppThemeMode.light;
    }
  }

  /// 循环切换主题
  Future<void> cycleTheme() async {
    await setThemeMode(nextThemeMode);
  }
}
