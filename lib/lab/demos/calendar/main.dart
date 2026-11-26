import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/calendar/presentation/calendar_page.dart';
import '../../../core/theme/app_theme.dart';

/// 独立入口：只跑日历页，用于把 HTML 原型
/// （docs/prototypes/calendar-capsule-nav.html）逐像素对到 Flutter 实现上。
///
/// 单独启动（不影响主应用）：
///   flutter run -d web-server -t lib/lab/demos/calendar/main.dart
///
/// 调试直达（URL hash）：
///   #year / #month / #week / #day / #agenda —— 指定首个页签
///   #dark —— 叠加暗色，验证主题通道
///
/// ⚠️ 正式入口仍是 `lib/lab/demos/calendar_demo.dart`（lab 里的「日历」卡片）。
/// 本文件只是调试壳，页面本体始终是 [CalendarPage]，改这里不会分叉实现。
void main() {
  // 调试壳：把构建期异常打到 console（release web 默认静默），便于
  // 无头浏览器自动对像素时定位「白屏」到底是哪一层炸了。
  FlutterError.onError = (details) {
    // ignore: avoid_print
    print('FLUTTER_ERROR ${details.exceptionAsString()}');
    FlutterError.presentError(details);
  };
  runZonedGuarded(
    () => runApp(const ProviderScope(child: _CalendarHarnessApp())),
    // ignore: avoid_print
    (error, stack) => print('ZONE_ERROR $error'),
  );
}

class _CalendarHarnessApp extends StatelessWidget {
  const _CalendarHarnessApp();

  static int _tabFromKey(String key) {
    return switch (key) {
      'year' => 0,
      'month' => 1,
      'week' => 2,
      'day' => 3,
      'agenda' => 4,
      _ => 1,
    };
  }

  @override
  Widget build(BuildContext context) {
    // 两种写法都认：`?tab=year&collapsed=1&dark=1`（自动化用）与
    // `#year`（人手敲）。query 优先。
    final query = Uri.base.queryParameters;
    final frag = Uri.base.fragment;
    final key = query['tab'] ?? frag;
    final dark = query.containsKey('dark') || frag.contains('dark');
    final collapsed = query.containsKey('collapsed');
    final AppThemeMode mode = dark ? AppThemeMode.dark : AppThemeMode.zen;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '茶禅日历',
      theme: AppTheme.getThemeData(mode),
      home: Scaffold(
        body: CalendarPage(
          initialTab: _tabFromKey(key),
          initialCollapsed: collapsed,
        ),
      ),
    );
  }
}
