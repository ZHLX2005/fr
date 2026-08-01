// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'body_record.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

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

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BodyRecordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
