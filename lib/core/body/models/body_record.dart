import 'package:hive_flutter/hive_flutter.dart';

@HiveType(typeId: 0)
class BodyRecord extends HiveObject {
  @HiveField(0)
  final String bodyPartId;

  @HiveField(1)
  final String content;

  @HiveField(2)
  final int? painLevel;

  @HiveField(3)
  final DateTime createdAt;

  BodyRecord({
    required this.bodyPartId,
    required this.content,
    this.painLevel,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}

class BodyRecordAdapter extends TypeAdapter<BodyRecord> {
  @override
  final int typeId = 0;

  @override
  BodyRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return BodyRecord(
      bodyPartId: fields[0] as String,
      content: fields[1] as String,
      painLevel: fields[2] as int?,
      createdAt: fields[3] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, BodyRecord obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.bodyPartId)
      ..writeByte(1)
      ..write(obj.content)
      ..writeByte(2)
      ..write(obj.painLevel)
      ..writeByte(3)
      ..write(obj.createdAt);
  }
}
