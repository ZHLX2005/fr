import 'package:home_widget/home_widget.dart';
import 'clock_widget_data.dart';

/// 桌面时钟小组件服务
/// 负责 Flutter 与原生 Android Widget 的数据通信
class ClockWidgetService {
  // Android Widget 配置
  static const String _androidWidgetName = 'ClockWidgetProvider';

  // SharedPreferences keys
  static const String _keyTitle = 'clock_title';
  static const String _keyRemainingSeconds = 'clock_remaining_seconds';
  static const String _keyDurationSeconds = 'clock_duration_seconds';
  static const String _keyIsRunning = 'clock_is_running';
  static const String _keyColor = 'clock_color';
  static const String _keyFormattedTime = 'clock_formatted_time';
  static const String _keyIsOvertime = 'clock_is_overtime';

  /// 更新桌面时钟小组件数据
  static Future<void> updateClockWidget(ClockWidgetData data) async {
    try {
      // 保存数据到原生存储
      await HomeWidget.saveWidgetData(_keyTitle, data.title);
      await HomeWidget.saveWidgetData(_keyRemainingSeconds, data.remainingSeconds.toString());
      await HomeWidget.saveWidgetData(_keyDurationSeconds, data.durationSeconds.toString());
      await HomeWidget.saveWidgetData(_keyIsRunning, data.isRunning ? '1' : '0');
      await HomeWidget.saveWidgetData(_keyColor, data.color);
      await HomeWidget.saveWidgetData(_keyFormattedTime, data.formattedTime);
      await HomeWidget.saveWidgetData(_keyIsOvertime, data.isOvertime ? '1' : '0');

      // 触发 Widget 更新
      await HomeWidget.updateWidget(
        name: _androidWidgetName,
        androidName: _androidWidgetName,
      );
    } catch (e) {
      // 静默处理错误，Widget 更新失败不影响主应用
    }
  }

  /// 清除小组件数据
  static Future<void> clearClockWidget() async {
    await updateClockWidget(ClockWidgetData.empty);
  }
}
