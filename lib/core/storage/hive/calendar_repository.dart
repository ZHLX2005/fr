import 'package:hive_flutter/hive_flutter.dart';

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
    _registerToStorageRegistry();
    _initialized = true;
  }

  Box<Event> get events => Hive.box<Event>(eventsBoxName);
  Box<Person> get people => Hive.box<Person>(peopleBoxName);
  Box<dynamic> get viewState => Hive.box(viewStateBoxName);

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
  }
}