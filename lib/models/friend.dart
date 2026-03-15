import 'package:json_annotation/json_annotation.dart';
import 'user.dart';

part 'friend.g.dart';

enum FriendStatus { pending, accepted, blocked }

@JsonSerializable()
class Friend {
  final String id;
  final User user;
  final FriendStatus status;
  final String? remark;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Friend({
    required this.id,
    required this.user,
    this.status = FriendStatus.accepted,
    this.remark,
    required this.createdAt,
    this.updatedAt,
  });

  factory Friend.fromJson(Map<String, dynamic> json) => _$FriendFromJson(json);

  Map<String, dynamic> toJson() => _$FriendToJson(this);

  String get displayName => remark?.isNotEmpty == true ? remark! : user.nickname;

  Friend copyWith({
    String? id,
    User? user,
    FriendStatus? status,
    String? remark,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Friend(
      id: id ?? this.id,
      user: user ?? this.user,
      status: status ?? this.status,
      remark: remark ?? this.remark,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

@JsonSerializable()
class FriendRequest {
  final String id;
  final String fromUserId;
  final String toUserId;
  final String? message;
  final bool isAccepted;
  final DateTime createdAt;

  FriendRequest({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    this.message,
    this.isAccepted = false,
    required this.createdAt,
  });

  factory FriendRequest.fromJson(Map<String, dynamic> json) =>
      _$FriendRequestFromJson(json);

  Map<String, dynamic> toJson() => _$FriendRequestToJson(this);
}
