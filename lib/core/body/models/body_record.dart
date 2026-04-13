import 'package:hive_flutter/hive_flutter.dart';

part 'body_record.g.dart';

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
