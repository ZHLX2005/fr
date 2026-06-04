import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'timetable_widget_data.dart';

/// 桌面课表小组件服务
///
/// 同步策略（按用户要求弱化）：
/// - 不做 1Hz 高频 tick
/// - 用户在课表页面修改课程后调用 [updateTimetableWidget] 一次性写入
/// - 整个 7×5 网格序列化为 JSON 一次性写入 SharedPreferences
/// - 即使主 app 进程被系统杀掉，下次系统 30 分钟周期或用户手动刷新时仍能正确显示
class TimetableWidgetService {
  // 必须用 qualifiedAndroidName 全限定类名，否则 home_widget 插件拼包名 + 简单类名
  // 找不到子包 .native.widget 下的 Provider，ClassNotFoundException 被静默吞掉。
  static const String _qualifiedAndroidName =
      'io.github.xiaodouzi.fr.native.widget.TimetableWidgetProvider';

  static const String _keyJson = 'timetable_widget_json';
  static const String _keyUpdatedAt = 'timetable_widget_updated_at';

  static bool _isUpdating = false;

  /// 推送课表数据到桌面小组件
  ///
  /// - [data] 完整课表数据
  /// - 调用后桌面组件会自动刷新
  static Future<void> updateTimetableWidget(TimetableWidgetData data) async {
    if (_isUpdating) return;
    _isUpdating = true;
    try {
      // 一次性写两个 key：完整数据 + 更新时间戳
      await Future.wait([
        HomeWidget.saveWidgetData(_keyJson, data.toJsonString()),
        HomeWidget.saveWidgetData(
          _keyUpdatedAt,
          DateTime.now().millisecondsSinceEpoch.toString(),
        ),
      ]);
      await HomeWidget.updateWidget(qualifiedAndroidName: _qualifiedAndroidName);
    } catch (e, stack) {
      debugPrint(
        '[TimetableWidgetService] updateTimetableWidget failed: $e\n$stack',
      );
    } finally {
      _isUpdating = false;
    }
  }

  /// 清除桌面组件数据（写一个空数据）
  static Future<void> clearTimetableWidget() async {
    await updateTimetableWidget(TimetableWidgetData.empty);
  }
}
