import 'package:hive/hive.dart';

import '../../../../core/storage/hive_type_ids.dart';
import '../data/calendar_config.dart';
import '../domain/event.dart';
import '../domain/recurrence.dart';

/// Event 类型的 Hive TypeAdapter（手写）
///
/// 为什么手写：hive_generator 2.0.1 的枚举序列化格式
/// （`writeByte(枚举typeId) + index`）与既有的 index-int 数据不兼容，
/// 手写 adapter 用 `obj.type.index` / `values[index]` 保证旧数据可读。
/// typeId 由 [HiveTypeIds] 集中分配。
class EventAdapter extends TypeAdapter<Event> {
  @override
  final int typeId = HiveTypeIds.calendarEvent;

  @override
  Event read(BinaryReader reader) {
    final fields = <int, dynamic>{};
    final count = reader.readByte();
    for (var i = 0; i < count; i++) {
      final key = reader.readByte();
      fields[key] = reader.read();
    }
    return Event(
      id: fields[0] as String,
      type: EventType.values[fields[1] as int],
      title: fields[2] as String,
      system: CalendarSystem.values[fields[3] as int],
      year: fields[4] as int,
      month: fields[5] as int,
      day: fields[6] as int,
      solarYearOffset: fields[7] as int?,
      recurrence: Recurrence.values[fields[8] as int],
      personId: fields[9] as String?,
      colorTag: ColorTag.values[fields[10] as int],
      note: fields[11] as String?,
      systemCalendarEventId: fields[12] as int?,
      lunarAnchorYear: fields[13] as int?,
      createdAt: fields[14] as DateTime,
      isLeap: (fields[15] as bool?) ?? false,
      groupId: (fields[16] as String?) ?? CalendarGroup.defaultGroupId,
    );
  }

  @override
  void write(BinaryWriter writer, Event obj) {
    writer
      ..writeByte(18)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.type.index)
      ..writeByte(2)
      ..write(obj.title)
      ..writeByte(3)
      ..write(obj.system.index)
      ..writeByte(4)
      ..write(obj.year)
      ..writeByte(5)
      ..write(obj.month)
      ..writeByte(6)
      ..write(obj.day)
      ..writeByte(7)
      ..write(obj.solarYearOffset)
      ..writeByte(8)
      ..write(obj.recurrence.index)
      ..writeByte(9)
      ..write(obj.personId)
      ..writeByte(10)
      ..write(obj.colorTag.index)
      ..writeByte(11)
      ..write(obj.note)
      ..writeByte(12)
      ..write(obj.systemCalendarEventId)
      ..writeByte(13)
      ..write(obj.lunarAnchorYear)
      ..writeByte(14)
      ..write(obj.createdAt)
      ..writeByte(15)
      ..write(obj.isLeap)
      ..writeByte(16)
      ..write(obj.groupId)
      ..writeByte(17)
      ..write(obj.everyNDays);
  }
}
