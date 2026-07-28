import 'package:hive_flutter/hive_flutter.dart';

import '../../../../core/storage/box_descriptor.dart';
import '../../../../core/storage/storage_registry.dart';
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
    // 注册到 StorageRegistry（面板自动接管展示 / 格式化 / 删除）
    StorageRegistry.register(BoxDescriptor<Event>(
      name: eventsBoxName,
      displayName: '日历事件',
      typeId: _eventTypeId,
      openTyped: () => Hive.openBox<Event>(eventsBoxName),
      formatValue: (v) {
        final e = v as Event;
        final parts = <String>[
          '标题: ${e.title}',
          '类型: ${e.type.name}',
          '历法: ${e.system.name}',
          '日期: ${e.month}月${e.day}日',
          '重复: ${e.recurrence.name}',
          if (e.personId != null) '关联人: ${e.personId}',
          if (e.note != null) '备注: ${e.note}',
        ];
        return parts.join('\n');
      },
    ));
    StorageRegistry.register(BoxDescriptor<Person>(
      name: peopleBoxName,
      displayName: '人物档案',
      typeId: _personTypeId,
      openTyped: () => Hive.openBox<Person>(peopleBoxName),
      formatValue: (v) {
        final p = v as Person;
        final parts = <String>[
          '姓名: ${p.name}',
          '关系: ${p.relation.name}',
          if (p.avatarEmoji != null) '头像: ${p.avatarEmoji}',
          if (p.note != null) '备注: ${p.note}',
        ];
        return parts.join('\n');
      },
    ));
    StorageRegistry.register(BoxDescriptor(
      name: viewStateBoxName,
      displayName: '日历视图状态',
      openUntyped: () => Hive.openBox(viewStateBoxName),
    ));
    _initialized = true;
  }

  /// Events Box（typed）
  static Box<Event> get events => Hive.box<Event>(eventsBoxName);

  /// People Box（typed）
  static Box<Person> get people => Hive.box<Person>(peopleBoxName);

  /// ViewState Box（非 typed，存 year/month）
  static Box get viewState => Hive.box(viewStateBoxName);
}