import 'package:json_annotation/json_annotation.dart';

part 'user.g.dart';

@JsonSerializable()
class User {
  final String id;
  final String nickname;
  final String? avatar;
  final String status; // online, offline, away
  final String? signature;
  final DateTime createdAt;

  User({
    required this.id,
    required this.nickname,
    this.avatar,
    this.status = 'offline',
    this.signature,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);

  Map<String, dynamic> toJson() => _$UserToJson(this);

  User copyWith({
    String? id,
    String? nickname,
    String? avatar,
    String? status,
    String? signature,
    DateTime? createdAt,
  }) {
    return User(
      id: id ?? this.id,
      nickname: nickname ?? this.nickname,
      avatar: avatar ?? this.avatar,
      status: status ?? this.status,
      signature: signature ?? this.signature,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
