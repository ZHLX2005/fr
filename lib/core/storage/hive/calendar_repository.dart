import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../lab/demos/calendar/data/calendar_config.dart';
import '../../../lab/demos/calendar/data/person_adapter.dart';
import '../../../lab/demos/calendar/domain/event.dart';
import '../../../lab/demos/calendar/domain/person.dart';
import '../box_descriptor.dart';
import '../hive_type_ids.dart';
import '../storage_registry.dart';
import 'hive_repository.dart';
import 'hive_store.dart';

/// v2: events box 改为 untyped Map（参考 groups 已有的做法）。
///
/// v1 的 typed `Box<Event>` 在 Event 模型变更后无法保留老数据。
/// 升级首次启动由 `EventV1Migration.run` 一次性迁移；
/// 此后所有 read/write 都以 `Map<String, dynamic>` 形式进出。
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
    // events 改为 untyped（v2）
    await HiveStore.instance.openUntyped(eventsBoxName);
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

  Box<dynamic> get events => Hive.box<dynamic>(eventsBoxName);
  Box<Person> get people => Hive.box<Person>(peopleBoxName);
  Box<dynamic> get viewState => Hive.box(viewStateBoxName);
  Box<dynamic> get groups => Hive.box(groupsBoxName);

  /// 加载所有 events；尝试 fromJson，失败跳过。
  List<Event> loadEvents() {
    final out = <Event>[];
    for (final key in events.keys) {
      final v = events.get(key);
      if (v is Map) {
        try {
          out.add(Event.fromJson(Map<String, dynamic>.from(v)));
        } catch (_) {
          // skip malformed
        }
      }
    }
    return out;
  }

  Future<void> saveEvent(Event e) async {
    await events.put(e.id, e.toJson());
  }

  Future<void> deleteEvent(String id) async {
    await events.delete(id);
  }

  Future<void> clearEvents() async {
    await events.clear();
  }

  // ──── group 管理（仿 timetable 多空间）──────

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

  Future<void> saveGroup(CalendarGroup group) async {
    if (group.id == CalendarGroup.defaultGroupId) return;
    await groups.put(group.id, group.toJson());
  }

  Future<void> deleteGroup(String id) async {
    if (id == CalendarGroup.defaultGroupId) return;
    await groups.delete(id);
    final activeId = await getActiveGroupId();
    if (activeId == id) {
      await setActiveGroup(CalendarGroup.defaultGroupId);
    }
  }

  Future<String> getActiveGroupId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_activeGroupKey);
    if (id == null) return CalendarGroup.defaultGroupId;
    if (id == CalendarGroup.defaultGroupId) return id;
    if (groups.containsKey(id)) return id;
    return CalendarGroup.defaultGroupId;
  }

  Future<void> setActiveGroup(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeGroupKey, id);
  }

  void _registerToStorageRegistry() {
    if (!StorageRegistry.has(eventsBoxName)) {
      StorageRegistry.register(BoxDescriptor(
        name: eventsBoxName,
        displayName: '日历事件',
        openUntyped: () => HiveStore.instance.openUntyped(eventsBoxName),
        formatValue: (v) {
          if (v is! Map) return v.toString();
          final title = v['title']?.toString() ?? '未命名';
          final type = v['type']?.toString() ?? '';
          return '标题: $title\n类型: $type';
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