import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'clock_widget_data.dart';

/// 桌面时钟小组件服务
/// 负责 Flutter 与原生 Android Widget 的数据通信
class ClockWidgetService {
  // Android Widget 全限定类名。home_widget 默认拼 "${packageName}.${name}"，
  // 但本项目 Provider 在子包下，必须用 qualifiedAndroidName 传完整类路径，
  // 否则 Class.forName 抛 ClassNotFoundException、onUpdate 永远不会被触发。
  static const String _qualifiedAndroidName =
      'io.github.xiaodouzi.fr.native.widget.ClockWidgetProvider';

  // SharedPreferences keys —— 只下发 Kotlin 侧真正会读的 6 个。
  //
  // 注意：HomeWidget.saveWidgetData 底层是 **commit()（同步落盘）**，不是 apply()。
  // 所以每多一个 key 都是实打实的一次磁盘提交，不要随手加。
  //
  // 刻意**不**下发的 4 个（Kotlin 侧从不读取，纯浪费）：
  //   clock_duration_seconds —— isPausedAtStart 已由 Dart 算好下发
  //   clock_color            —— 颜色走 Kotlin 侧 style.color 常量
  //   clock_formatted_time   —— Kotlin 用自己的 formatHms()
  //   clock_is_overtime      —— 时变量，Kotlin 用 remainingMs < 0 自算
  static const String _keyTitle = 'clock_title';
  static const String _keyRemainingSeconds = 'clock_remaining_seconds';
  static const String _keyIsRunning = 'clock_is_running';
  static const String _keyStartTimeMs = 'clock_start_time_ms';
  static const String _keyStartRemainingSeconds =
      'clock_start_remaining_seconds';
  static const String _keyIsPausedAtStart = 'clock_is_paused_at_start';

  // 「最新帧必胜」的串行合并链。
  //
  // 早期实现是 `if (_isUpdating) return;` —— 那会**静默丢掉最新帧**：
  // startCountdown 的推送还在飞时用户立刻点暂停，暂停态就永远写不出去，
  // widget 会顽固地停在「进行中」。推送降到低频后单次丢失更显眼，必须修掉。
  static Future<void> _chain = Future<void>.value();
  static ClockWidgetData? _pending;

  /// 更新桌面时钟小组件数据。
  ///
  /// 并发调用时中间态自动合并、最终态一定会被写出。
  static Future<void> updateClockWidget(ClockWidgetData data) {
    _pending = data;
    _chain = _chain.then((_) async {
      final next = _pending;
      if (next == null) return;
      _pending = null;
      try {
        await _write(next);
      } catch (e, stack) {
        debugPrint('[ClockWidgetService] updateClockWidget failed: $e\n$stack');
      }
    });
    return _chain;
  }

  static Future<void> _write(ClockWidgetData data) async {
    // 并发写入所有键，比顺序 await 快 ~9 倍；home_widget 内部用同一份
    // SharedPreferences，并发安全。
    await Future.wait([
      HomeWidget.saveWidgetData(_keyTitle, data.title),
      HomeWidget.saveWidgetData(
        _keyRemainingSeconds,
        data.remainingSeconds.toString(),
      ),
      HomeWidget.saveWidgetData(_keyIsRunning, data.isRunning ? '1' : '0'),
      HomeWidget.saveWidgetData(_keyStartTimeMs, data.startTimeMs.toString()),
      HomeWidget.saveWidgetData(
        _keyStartRemainingSeconds,
        data.startRemainingSeconds.toString(),
      ),
      HomeWidget.saveWidgetData(
        _keyIsPausedAtStart,
        data.isPausedAtStart ? '1' : '0',
      ),
    ]);

    // 用全限定类名触发 onUpdate；这里之前传简单类名 'ClockWidgetProvider'，
    // 插件拼成 "${packageName}.ClockWidgetProvider" → ClassNotFoundException，
    // 异常被插件 catch 静默掉，导致 widget 只能等系统 30 分钟周期刷新。
    await HomeWidget.updateWidget(
      qualifiedAndroidName: _qualifiedAndroidName,
    );
  }

  /// 清除小组件数据
  static Future<void> clearClockWidget() async {
    await updateClockWidget(ClockWidgetData.empty);
  }
}
