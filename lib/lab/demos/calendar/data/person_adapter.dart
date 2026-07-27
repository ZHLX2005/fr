import 'package:hive/hive.dart';

import '../domain/person.dart';

/// Person 类型的 Hive TypeAdapter
///
/// typeId = 91
class PersonAdapter extends TypeAdapter<Person> {
  @override
  final int typeId = 91;

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
    );
  }

  @override
  void write(BinaryWriter writer, Person obj) {
    writer
      ..writeByte(6)
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
      ..write(obj.createdAt);
  }
}