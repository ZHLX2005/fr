import 'package:hive_flutter/hive_flutter.dart';

import '../../storage/hive_type_ids.dart';

part 'pi_chat_message.g.dart';

/// pi 聊天模块的一条本地消息（Hive 持久化）。
///
/// 与服务端 SSE 的对应关系：
/// - user 消息：来自 [PiSseEvent] role=user 的 message_start/end（服务端回显）
/// - assistant 消息：text_delta 增量拼接，message_end 时以 [text] 终稿覆盖
///
/// 本地存储是**对话 UI 的真相源**：断网/重启后从 Hive 回读即可恢复会话画面；
/// 服务端 JSONL 是完整真相，本地只是缓存（可用「服务端历史回读」重建）。
@HiveType(typeId: HiveTypeIds.piChatMessage)
class PiChatMessage extends HiveObject {
  /// pi 服务端 sessionId（同一会话的多条消息共用）。
  @HiveField(0)
  final String sessionId;

  /// user / assistant。
  @HiveField(1)
  final String role;

  /// 消息文本（assistant 流式过程中逐步补全，final 时一次写入）。
  @HiveField(2)
  String text;

  /// 本地生成时间。
  @HiveField(3)
  final DateTime createdAt;

  /// assistant 消息是否已完成（false = 还在流式）。
  @HiveField(4)
  bool done;

  /// 使用的模型（`provider/modelId`），assistant 侧记录。
  @HiveField(5)
  final String? model;

  /// 出错信息（prompt 被拒/网络失败时记录，UI 显示错误气泡）。
  @HiveField(6)
  String? error;

  /// 发送中标志（本地乐观 UI：用户消息落库时还没有服务端回执）。
  @HiveField(7)
  bool pending;

  PiChatMessage({
    required this.sessionId,
    required this.role,
    required this.text,
    DateTime? createdAt,
    this.done = true,
    this.model,
    this.error,
    this.pending = false,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 用于 Hive key：同一会话内按时间排序且唯一。
  String keyFor(int seq) => '$sessionId#$seq';

  @override
  String toString() =>
      'PiChatMessage($role, ${text.length}字${error != null ? ', err' : ''})';
}
