// 主题状态管理（Riverpod 版）。
//
// 历史：原本是 ChangeNotifier，由 `provider` 包持有，依赖 StatefulWidget。
// 问题：
//   - lifecycle 不清晰（StatefulWidget.initState 创建，.value() 注入）
//   - 与其它 Riverpod 业务混用，DI 体系分裂
//   - 不可测（无法 override）
//
// 设计：
//   - ThemeNotifier extends Notifier<AppThemeMode>：单一状态源
//   - themeDataProvider / materialThemeModeProvider：派生 Provider
//   - 持久化：main() 启动前 await hydrate() 同步加载，setMode 时落盘

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_theme.dart';

export '../app_theme.dart' show AppTheme, AppThemeMode;

/// SharedPreferences key（与历史值保持一致，避免旧用户回退到默认主题）
const _kThemeKey = 'app_theme_mode';

/// 主题状态 Notifier。
///
/// - `state`：当前 AppThemeMode
/// - `hydrate()`：main() runApp 前 await，从 SharedPreferences 同步加载并 setState
/// - `setMode(mode)`：切换主题 + 持久化
class ThemeNotifier extends Notifier<AppThemeMode> {
  @override
  AppThemeMode build() {
    // 同步给出 default，避免 build 阶段空值
    // 真实持久化值由外部 hydrate() 在 runApp 前覆盖
    return AppThemeMode.zen;
  }

  /// 从 SharedPreferences 同步加载持久化主题。
  ///
  /// 由 main() 在 runApp 之前调用一次。
  Future<void> hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kThemeKey);
    if (saved == null) return;
    final m = AppThemeMode.values.firstWhere(
      (e) => e.name == saved,
      orElse: () => AppThemeMode.zen,
    );
    state = m;
  }

  /// 切换主题并落盘。
  Future<void> setMode(AppThemeMode mode) async {
    if (state == mode) return;
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeKey, mode.name);
  }
}

/// 主入口：当前主题模式。
final themeNotifierProvider =
    NotifierProvider<ThemeNotifier, AppThemeMode>(ThemeNotifier.new);

/// 派生：ThemeData（每次 mode 变化重建）。
final themeDataProvider = Provider<ThemeData>((ref) {
  final mode = ref.watch(themeNotifierProvider);
  return AppTheme.getThemeData(mode);
});

/// 派生：Material ThemeMode（深色主题对应 Material dark）。
final materialThemeModeProvider = Provider<ThemeMode>((ref) {
  final mode = ref.watch(themeNotifierProvider);
  return switch (mode) {
    AppThemeMode.purple => ThemeMode.dark,
    _ => ThemeMode.light,
  };
});