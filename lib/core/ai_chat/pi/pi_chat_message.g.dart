// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pi_chat_message.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PiChatMessageAdapter extends TypeAdapter<PiChatMessage> {
  @override
  final int typeId = 1;

  @override
  PiChatMessage read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PiChatMessage(
      sessionId: fields[0] as String,
      role: fields[1] as String,
      text: fields[2] as String,
      createdAt: fields[3] as DateTime?,
      done: fields[4] as bool,
      model: fields[5] as String?,
      error: fields[6] as String?,
      pending: fields[7] as bool,
      stopped: fields[8] == null ? false : fields[8] as bool,
      toolActivity: fields[10] == null ? '' : fields[10] as String,
      imageCount: fields[11] == null ? 0 : fields[11] as int,
      firstImageThumb: fields[12] == null ? '' : fields[12] as String,
      id: fields[9] == null ? '' : fields[9] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, PiChatMessage obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.sessionId)
      ..writeByte(1)
      ..write(obj.role)
      ..writeByte(2)
      ..write(obj.text)
      ..writeByte(3)
      ..write(obj.createdAt)
      ..writeByte(4)
      ..write(obj.done)
      ..writeByte(5)
      ..write(obj.model)
      ..writeByte(6)
      ..write(obj.error)
      ..writeByte(7)
      ..write(obj.pending)
      ..writeByte(8)
      ..write(obj.stopped)
      ..writeByte(9)
      ..write(obj.id)
      ..writeByte(11)
      ..write(obj.imageCount)
      ..writeByte(12)
      ..write(obj.firstImageThumb)
      ..writeByte(10)
      ..write(obj.toolActivity);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PiChatMessageAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
