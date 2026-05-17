import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'calendar_widget_data.dart';

/// 桌面日历小组件服务
///
/// 与 ClockWidgetService 同一套路：必须用 qualifiedAndroidName 全限定类名，
/// 否则 home_widget 插件 Class.forName 拼包名会找不到 .native.widget 子包下的 Provider。
class CalendarWidgetService {
  static const String _qualifiedAndroidName =
      'io.github.xiaodouzi.fr.native.widget.CalendarWidgetProvider';

  static const String _keyYear = 'calendar_year';
  static const String _keyMonth = 'calendar_month';
  static const String _keyTodayYear = 'calendar_today_year';
  static const String _keyTodayMonth = 'calendar_today_month';
  static const String _keyTodayDay = 'calendar_today_day';
  static const String _keyColorsJson = 'calendar_colors_json';

  static bool _isUpdating = false;

  static Future<void> updateCalendarWidget(CalendarWidgetData data) async {
    if (_isUpdating) return;
    _isUpdating = true;
    try {
      await Future.wait([
        HomeWidget.saveWidgetData(_keyYear, data.year.toString()),
        HomeWidget.saveWidgetData(_keyMonth, data.month.toString()),
        HomeWidget.saveWidgetData(_keyTodayYear, data.todayYear.toString()),
        HomeWidget.saveWidgetData(_keyTodayMonth, data.todayMonth.toString()),
        HomeWidget.saveWidgetData(_keyTodayDay, data.todayDay.toString()),
        HomeWidget.saveWidgetData(_keyColorsJson, data.colorsJson),
      ]);
      await HomeWidget.updateWidget(
        qualifiedAndroidName: _qualifiedAndroidName,
      );
    } catch (e, stack) {
      debugPrint('[CalendarWidgetService] update failed: $e\n$stack');
    } finally {
      _isUpdating = false;
    }
  }

  static Future<void> clearCalendarWidget() async {
    await updateCalendarWidget(CalendarWidgetData.empty);
  }
}
