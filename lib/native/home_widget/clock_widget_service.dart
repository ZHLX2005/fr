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

  // SharedPreferences keys
  static const String _keyTitle = 'clock_title';
  static const String _keyRemainingSeconds = 'clock_remaining_seconds';
  static const String _keyDurationSeconds = 'clock_duration_seconds';
  static const String _keyIsRunning = 'clock_is_running';
  static const String _keyColor = 'clock_color';
  static const String _keyFormattedTime = 'clock_formatted_time';
  static const String _keyIsOvertime = 'clock_is_overtime';
  static const String _keyStartTimeMs = 'clock_start_time_ms';
  static const String _keyStartRemainingSeconds =
      'clock_start_remaining_seconds';

  // 并发更新去重：高频 tick 中若上一次还没写完，直接跳过新的请求避免堆积
  static bool _isUpdating = false;

  /// 更新桌面时钟小组件数据
  static Future<void> updateClockWidget(ClockWidgetData data) async {
    if (_isUpdating) return;
    _isUpdating = true;
    try {
      // 并发写入所有键，比顺序 await 快 ~9 倍；home_widget 内部用同一份
      // SharedPreferences，并发安全。
      await Future.wait([
        HomeWidget.saveWidgetData(_keyTitle, data.title),
        HomeWidget.saveWidgetData(
          _keyRemainingSeconds,
          data.remainingSeconds.toString(),
        ),
        HomeWidget.saveWidgetData(
          _keyDurationSeconds,
          data.durationSeconds.toString(),
        ),
        HomeWidget.saveWidgetData(_keyIsRunning, data.isRunning ? '1' : '0'),
        HomeWidget.saveWidgetData(_keyColor, data.color),
        HomeWidget.saveWidgetData(_keyFormattedTime, data.formattedTime),
        HomeWidget.saveWidgetData(_keyIsOvertime, data.isOvertime ? '1' : '0'),
        HomeWidget.saveWidgetData(
          _keyStartTimeMs,
          data.startTimeMs.toString(),
        ),
        HomeWidget.saveWidgetData(
          _keyStartRemainingSeconds,
          data.startRemainingSeconds.toString(),
        ),
      ]);

      // 用全限定类名触发 onUpdate；这里之前传简单类名 'ClockWidgetProvider'，
      // 插件拼成 "${packageName}.ClockWidgetProvider" → ClassNotFoundException，
      // 异常被插件 catch 静默掉，导致 widget 只能等系统 30 分钟周期刷新。
      await HomeWidget.updateWidget(
        qualifiedAndroidName: _qualifiedAndroidName,
      );
    } catch (e, stack) {
      debugPrint('[ClockWidgetService] updateClockWidget failed: $e\n$stack');
    } finally {
      _isUpdating = false;
    }
  }

  /// 清除小组件数据
  static Future<void> clearClockWidget() async {
    await updateClockWidget(ClockWidgetData.empty);
  }
}
