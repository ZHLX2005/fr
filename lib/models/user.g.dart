// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

User _$UserFromJson(Map<String, dynamic> json) => User(
  id: json['id'] as String,
  nickname: json['nickname'] as String,
  avatar: json['avatar'] as String?,
  status: json['status'] as String? ?? 'offline',
  signature: json['signature'] as String?,
  createdAt: DateTime.parse(json['createdAt'] as String),
);

Map<String, dynamic> _$UserToJson(User instance) => <String, dynamic>{
  'id': instance.id,
  'nickname': instance.nickname,
  'avatar': instance.avatar,
  'status': instance.status,
  'signature': instance.signature,
  'createdAt': instance.createdAt.toIso8601String(),
};
