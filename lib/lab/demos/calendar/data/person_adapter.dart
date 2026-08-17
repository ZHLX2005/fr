import 'package:hive/hive.dart';

import '../../../../core/storage/hive_type_ids.dart';
import '../data/calendar_config.dart';
import '../domain/person.dart';

/// Person 类型的 Hive TypeAdapter（手写）
///
/// 为什么手写：同 [EventAdapter] —— hive_generator 2.0.1 的枚举序列化
/// 与既有 index-int 数据不兼容。typeId 由 [HiveTypeIds] 集中分配。
class PersonAdapter extends TypeAdapter<Person> {
  @override
  final int typeId = HiveTypeIds.calendarPerson;

  @override
  Person read(BinaryReader reader) {
    final fields = <int, dynamic>{};
    final count = reader.readByte();
    for (var i = 0; i < count; i++) {
      final key = reader.readByte();
      fields[key] = reader.read();
    }
    return Person(
      id: fields[0] as String,
      name: fields[1] as String,
      relation: PersonRelation.values[fields[2] as int],
      avatarEmoji: fields[3] as String?,
      note: fields[4] as String?,
      createdAt: fields[5] as DateTime,
      groupId: (fields[6] as String?) ?? CalendarGroup.defaultGroupId,
    );
  }

  @override
  void write(BinaryWriter writer, Person obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.relation.index)
      ..writeByte(3)
      ..write(obj.avatarEmoji)
      ..writeByte(4)
      ..write(obj.note)
      ..writeByte(5)
      ..write(obj.createdAt)
      ..writeByte(6)
      ..write(obj.groupId);
  }
}
