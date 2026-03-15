import 'package:json_annotation/json_annotation.dart';
import 'message.dart';

part 'chat_session.g.dart';

@JsonSerializable()
class ChatSession {
  final String id;
  final String userId;
  final String? friendId;
  final String? groupName;
  final Message? lastMessage;
  final int unreadCount;
  final DateTime updatedAt;

  ChatSession({
    required this.id,
    required this.userId,
    this.friendId,
    this.groupName,
    this.lastMessage,
    this.unreadCount = 0,
    required this.updatedAt,
  });

  factory ChatSession.fromJson(Map<String, dynamic> json) =>
      _$ChatSessionFromJson(json);

  Map<String, dynamic> toJson() => _$ChatSessionToJson(this);

  String get displayName => groupName ?? friendId ?? '未知';

  ChatSession copyWith({
    String? id,
    String? userId,
    String? friendId,
    String? groupName,
    Message? lastMessage,
    int? unreadCount,
    DateTime? updatedAt,
  }) {
    return ChatSession(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      friendId: friendId ?? this.friendId,
      groupName: groupName ?? this.groupName,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
