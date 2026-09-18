// lib/app_lifecycle/app_foreground.dart
//
// 全局「app 是否在前台」信号。
//
// 用途：让**非 widget 的常驻服务**（transport / discovery 等）也能在 app 退到
// 后台时挂起周期性工作，回前台再恢复 —— 否则它们会在后台继续心跳 / 组播 / 采样，
// 被系统记成后台耗电。
//
// 为什么不各自实现 `WidgetsBindingObserver`：
//   1. transport / discovery 不是 State，拿不到 observer 的天然挂载点；
//   2. 4+ 处重复的 observe/unobserve 样板容易漏掉 removeObserver（内存泄漏）；
//   3. 只认 `paused` / `resumed` 这一个判定的口径需要统一 —— `inactive` 会被
//      弹权限框、分屏、下拉通知栏频繁触发，误判成"进后台"会让服务反复挂起恢复。
//
// 页面（State）直接用自己的 `WidgetsBindingObserver` 判 `paused` 即可，
// 不必绕这一层。

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// 全局前后台状态。默认 true —— bootstrap 之前视为前台，避免误挂起。
class AppForeground {
  AppForeground._();

  static final ValueNotifier<bool> isForeground = ValueNotifier<bool>(true);

  static bool get value => isForeground.value;

  static _AppForegroundObserver? _observer;

  /// 在 app bootstrap 里调用一次（幂等）。
  static void install() {
    if (_observer != null) return;
    _observer = _AppForegroundObserver();
    WidgetsBinding.instance.addObserver(_observer!);
  }

  /// 测试钩子：直接置位，不依赖 Flutter 绑定。
  @visibleForTesting
  static void setForTest(bool foreground) => isForeground.value = foreground;

  @visibleForTesting
  static void resetForTest() {
    if (_observer != null) {
      WidgetsBinding.instance.removeObserver(_observer!);
      _observer = null;
    }
    isForeground.value = true;
  }
}

class _AppForegroundObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        AppForeground.isForeground.value = true;
      case AppLifecycleState.paused:
        AppForeground.isForeground.value = false;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // 刻意忽略：inactive 会被弹权限框 / 分屏 / 下拉通知栏触发，
        // 在这里翻转会让订阅方反复挂起恢复，形成新的抖动源。
        break;
    }
  }
}
