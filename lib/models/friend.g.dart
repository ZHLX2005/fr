// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'friend.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Friend _$FriendFromJson(Map<String, dynamic> json) => Friend(
  id: json['id'] as String,
  user: User.fromJson(json['user'] as Map<String, dynamic>),
  status:
      $enumDecodeNullable(_$FriendStatusEnumMap, json['status']) ??
      FriendStatus.accepted,
  remark: json['remark'] as String?,
  createdAt: DateTime.parse(json['createdAt'] as String),
  updatedAt: json['updatedAt'] == null
      ? null
      : DateTime.parse(json['updatedAt'] as String),
);

Map<String, dynamic> _$FriendToJson(Friend instance) => <String, dynamic>{
  'id': instance.id,
  'user': instance.user,
  'status': _$FriendStatusEnumMap[instance.status]!,
  'remark': instance.remark,
  'createdAt': instance.createdAt.toIso8601String(),
  'updatedAt': instance.updatedAt?.toIso8601String(),
};

const _$FriendStatusEnumMap = {
  FriendStatus.pending: 'pending',
  FriendStatus.accepted: 'accepted',
  FriendStatus.blocked: 'blocked',
};

FriendRequest _$FriendRequestFromJson(Map<String, dynamic> json) =>
    FriendRequest(
      id: json['id'] as String,
      fromUserId: json['fromUserId'] as String,
      toUserId: json['toUserId'] as String,
      message: json['message'] as String?,
      isAccepted: json['isAccepted'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );

Map<String, dynamic> _$FriendRequestToJson(FriendRequest instance) =>
    <String, dynamic>{
      'id': instance.id,
      'fromUserId': instance.fromUserId,
      'toUserId': instance.toUserId,
      'message': instance.message,
      'isAccepted': instance.isAccepted,
      'createdAt': instance.createdAt.toIso8601String(),
    };
