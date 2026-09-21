// 全局圆环开关状态。
//
// 与 activeGroupProvider 同构：页面 watch 取值、notifier 负责载入/持久化。
// 设置在 KV 清单页（圆环本身就是提交 KV 需求的入口，开关放它自己的功能页）。
//
// 启动时在 main() 里 hydrate 一次，避免首帧先画出圆环再消失。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'const_global_ring.dart';

final ringEnabledProvider =
    StateNotifierProvider<RingEnabledNotifier, bool>((ref) => RingEnabledNotifier());

class RingEnabledNotifier extends StateNotifier<bool> {
  RingEnabledNotifier() : super(ConstGlobalRing.defaultEnabled);

  /// 从 SharedPreferences 载入开关，失败回落默认值（圆环照常显示，
  /// 不影响提交入口的可用性）。
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(ConstGlobalRing.prefEnabled) ??
          ConstGlobalRing.defaultEnabled;
    } catch (_) {
      state = ConstGlobalRing.defaultEnabled;
    }
  }

  /// 设置开关并持久化；持久化失败不阻断本次切换（本次会话内仍生效）。
  Future<void> set(bool enabled) async {
    state = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(ConstGlobalRing.prefEnabled, enabled);
    } catch (_) {}
  }
}
