import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 系统日历服务
///
/// 通过 MethodChannel 与 Kotlin CalendarChannel 通信，
/// 提供权限检查、插入/删除系统日历事件的能力。
class CalendarService {
  static const _channel = MethodChannel('io.github.xiaodouzi.fr/calendar');

  /// 检查是否有日历读写权限
  static Future<bool> checkPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('checkPermission');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('[CalendarService] checkPermission failed: ${e.message}');
      return false;
    }
  }

  /// 请求日历读写权限
  static Future<void> requestPermission() async {
    try {
      await _channel.invokeMethod<void>('requestPermission');
    } on PlatformException catch (e) {
      debugPrint('[CalendarService] requestPermission failed: ${e.message}');
    }
  }

  /// 插入事件到系统日历
  ///
  /// 返回系统日历事件 ID，失败返回 null
  static Future<int?> insertEvent({
    required String title,
    required int year,
    required int month,
    required int day,
    String description = '',
  }) async {
    try {
      final result = await _channel.invokeMethod<int>('insertEvent', {
        'title': title,
        'description': description,
        'year': year,
        'month': month,
        'day': day,
      });
      return result;
    } on PlatformException catch (e) {
      debugPrint('[CalendarService] insertEvent failed: ${e.message}');
      return null;
    }
  }

  /// 删除系统日历中的事件
  static Future<bool> deleteEvent(int eventId) async {
    try {
      final result = await _channel.invokeMethod<bool>('deleteEvent', {
        'eventId': eventId,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('[CalendarService] deleteEvent failed: ${e.message}');
      return false;
    }
  }
}
