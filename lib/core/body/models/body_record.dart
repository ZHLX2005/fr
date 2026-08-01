import 'package:hive_flutter/hive_flutter.dart';

import '../../storage/hive_type_ids.dart';

part 'body_record.g.dart';

@HiveType(typeId: HiveTypeIds.bodyRecord)
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

  Map<String, dynamic> toJson() => {
        'bodyPartId': bodyPartId,
        'content': content,
        if (painLevel != null) 'painLevel': painLevel,
        'createdAt': createdAt.toIso8601String(),
      };

  factory BodyRecord.fromJson(Map<String, dynamic> json) => BodyRecord(
        bodyPartId: json['bodyPartId'] as String,
        content: json['content'] as String,
        painLevel: json['painLevel'] as int?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
