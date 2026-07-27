import 'package:hive_flutter/hive_flutter.dart';

import '../domain/event.dart';
import '../domain/person.dart';
import 'event_adapter.dart';
import 'person_adapter.dart';

/// 日历 demo 的 Hive 集中初始化
///
/// 调用顺序：
///   await CalendarHive.init();
///   Hive.box<Event>('calendarEvents') // 之后可访问
class CalendarHive {
  static const eventsBoxName = 'calendarEvents';
  static const peopleBoxName = 'calendarPeople';
  static const viewStateBoxName = 'calendarViewState';

  static const _eventTypeId = 90;
  static const _personTypeId = 91;

  static bool _initialized = false;
  static bool _hiveFlutterInited = false;

  /// 注册 Adapter + 打开 Box（幂等）
  ///
  /// 兼容 storage_analyze_demo 之外的直接打开场景。
  static Future<void> init() async {
    if (_initialized) return;
    // 先尝试 initFlutter（如果 StorageManager 已经做过，会立即返回）
    if (!_hiveFlutterInited) {
      try {
        await Hive.initFlutter();
      } catch (_) {
        // 已初始化；忽略（典型情况：StorageManager 先打开 body_records 时已 initFlutter）
      }
      _hiveFlutterInited = true;
    }
    // 注册 adapter（即使 box 已开也注册，下次开新 box 用得上）
    if (!Hive.isAdapterRegistered(_eventTypeId)) {
      Hive.registerAdapter(EventAdapter());
    }
    if (!Hive.isAdapterRegistered(_personTypeId)) {
      Hive.registerAdapter(PersonAdapter());
    }
    // 打开 box（已开则跳过）
    if (!Hive.isBoxOpen(eventsBoxName)) {
      await Hive.openBox<Event>(eventsBoxName);
    }
    if (!Hive.isBoxOpen(peopleBoxName)) {
      await Hive.openBox<Person>(peopleBoxName);
    }
    if (!Hive.isBoxOpen(viewStateBoxName)) {
      await Hive.openBox(viewStateBoxName);
    }
    _initialized = true;
  }

  /// Events Box（typed）
  static Box<Event> get events => Hive.box<Event>(eventsBoxName);

  /// People Box（typed）
  static Box<Person> get people => Hive.box<Person>(peopleBoxName);

  /// ViewState Box（非 typed，存 year/month）
  static Box get viewState => Hive.box(viewStateBoxName);
}