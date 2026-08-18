import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../lab/demos/calendar/data/calendar_config.dart';
import '../../../lab/demos/calendar/data/event_adapter.dart';
import '../../../lab/demos/calendar/data/person_adapter.dart';
import '../../../lab/demos/calendar/domain/event.dart';
import '../../../lab/demos/calendar/domain/person.dart';
import '../box_descriptor.dart';
import '../hive_type_ids.dart';
import '../storage_registry.dart';
import 'hive_repository.dart';
import 'hive_store.dart';

class CalendarRepository implements HiveRepository {
  static const eventsBoxName = 'calendarEvents';
  static const peopleBoxName = 'calendarPeople';
  static const viewStateBoxName = 'calendarViewState';
  static const groupsBoxName = 'calendarGroups';
  static const _activeGroupKey = 'calendar-active-group';

  CalendarRepository._();
  static final CalendarRepository instance = CalendarRepository._();

  bool _initialized = false;

  @override
  String get boxName => eventsBoxName;

  Future<void> init() async {
    if (_initialized) return;
    await HiveStore.instance.openTyped<Event>(
      eventsBoxName,
      adapter: EventAdapter(),
      typeId: HiveTypeIds.calendarEvent,
    );
    await HiveStore.instance.openTyped<Person>(
      peopleBoxName,
      adapter: PersonAdapter(),
      typeId: HiveTypeIds.calendarPerson,
    );
    await HiveStore.instance.openUntyped(viewStateBoxName);
    await HiveStore.instance.openUntyped(groupsBoxName);
    _registerToStorageRegistry();
    _initialized = true;
  }

  Box<Event> get events => Hive.box<Event>(eventsBoxName);
  Box<Person> get people => Hive.box<Person>(peopleBoxName);
  Box<dynamic> get viewState => Hive.box(viewStateBoxName);
  Box<dynamic> get groups => Hive.box(groupsBoxName);

  // ──── group 管理（仿 timetable 多空间）──────

  /// 加载所有 group（default 永远存在）
  Future<List<CalendarGroup>> loadGroups() async {
    final list = <CalendarGroup>[const CalendarGroup(
      id: CalendarGroup.defaultGroupId,
      name: '默认日历',
      createdAt: 0,
    )];
    for (final key in groups.keys) {
      final v = groups.get(key);
      if (v is Map) {
        list.add(CalendarGroup.fromJson(v.map((k, e) => MapEntry(k.toString(), e))));
      }
    }
    return list;
  }

  /// 保存（新建或更新）一个 group
  Future<void> saveGroup(CalendarGroup group) async {
    if (group.id == CalendarGroup.defaultGroupId) {
      // default 组不可写（不可改 id/name）
      return;
    }
    await groups.put(group.id, group.toJson());
  }

  /// 删除一个 group（default 不可删）
  Future<void> deleteGroup(String id) async {
    if (id == CalendarGroup.defaultGroupId) return;
    await groups.delete(id);
    // 若删除的是当前激活组，回退 default
    final activeId = await getActiveGroupId();
    if (activeId == id) {
      await setActiveGroup(CalendarGroup.defaultGroupId);
    }
  }

  /// 读取当前激活 group id（默认 'default'）
  Future<String> getActiveGroupId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_activeGroupKey);
    if (id == null) return CalendarGroup.defaultGroupId;
    // 校验 group 存在
    if (id == CalendarGroup.defaultGroupId) return id;
    if (groups.containsKey(id)) return id;
    return CalendarGroup.defaultGroupId;
  }

  /// 切换激活 group
  Future<void> setActiveGroup(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeGroupKey, id);
  }

  void _registerToStorageRegistry() {
    if (!StorageRegistry.has(eventsBoxName)) {
      StorageRegistry.register(BoxDescriptor<Event>(
        name: eventsBoxName,
        displayName: '日历事件',
        typeId: HiveTypeIds.calendarEvent,
        openTyped: () => HiveStore.instance.openTyped<Event>(
          eventsBoxName,
          adapter: EventAdapter(),
          typeId: HiveTypeIds.calendarEvent,
        ),
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
    }
    if (!StorageRegistry.has(peopleBoxName)) {
      StorageRegistry.register(BoxDescriptor<Person>(
        name: peopleBoxName,
        displayName: '日历联系人',
        typeId: HiveTypeIds.calendarPerson,
        openTyped: () => HiveStore.instance.openTyped<Person>(
          peopleBoxName,
          adapter: PersonAdapter(),
          typeId: HiveTypeIds.calendarPerson,
        ),
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
    }
    if (!StorageRegistry.has(viewStateBoxName)) {
      StorageRegistry.register(BoxDescriptor(
        name: viewStateBoxName,
        displayName: '日历视图状态',
        openUntyped: () => HiveStore.instance.openUntyped(viewStateBoxName),
        formatValue: (v) => v.toString(),
      ));
    }
    if (!StorageRegistry.has(groupsBoxName)) {
      StorageRegistry.register(BoxDescriptor(
        name: groupsBoxName,
        displayName: '日历空间',
        openUntyped: () => HiveStore.instance.openUntyped(groupsBoxName),
        formatValue: (v) {
          if (v is! Map) return v.toString();
          final name = v['name']?.toString() ?? '未命名';
          return name;
        },
      ));
    }
  }
}