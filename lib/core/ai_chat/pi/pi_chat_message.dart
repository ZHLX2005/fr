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

  /// assistant 消息被中止/中断（区别于自然完成；UI 显示「已停止」状态行
  /// 而不是把伪造文本混进正文 —— 复评 P2）。
  @HiveField(8, defaultValue: false)
  bool stopped;

  /// ★ 稳定身份（第 8 次复评 P1 根因）。
  ///
  /// 此前没有 id：定位气泡只能靠 `==`（sessionId+role+text）或下标 ——
  /// 两条正文为空的失败轮次**完全相等**，`indexOf` 恒定命中第一条 →
  /// 重发错内容、内存删错（留下 key==null 幽灵行）。
  /// 任何依赖「这一条气泡」的交互（重发/复制/删除）都必须用 id。
  @HiveField(9, defaultValue: '')
  String id;

  /// 本轮工具活动摘要（每行一个工具；纯工具轮靠它才不是空气泡）。
  /// agent 产品的核心信息：用户在等的时候需要看到「它在读文件/跑命令」。
  @HiveField(10, defaultValue: '')
  String toolActivity;

  PiChatMessage({
    required this.sessionId,
    required this.role,
    required this.text,
    DateTime? createdAt,
    this.done = true,
    this.model,
    this.error,
    this.pending = false,
    this.stopped = false,
    this.toolActivity = '',
    String? id,
  })  : id = id ?? _newId(),
        createdAt = createdAt ?? DateTime.now();

  /// 本地唯一 id（时间戳 + 计数器，无需外部 uuid 依赖）。
  static int _seq = 0;
  static String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

  /// 用于 Hive key：同一会话内按时间排序且唯一。
  String keyFor(int seq) => '$sessionId#$seq';

  /// 值相等（sessionId+role+text）—— 历史回读去重的依据。
  /// 此前没有重写 → Set/contains 做身份比较永远 miss → 每进一次会话
  /// 整段服务端历史重复落库一次（第 6 次复评探针 A：无界膨胀）。
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PiChatMessage &&
          other.sessionId == sessionId &&
          other.role == role &&
          other.text == text;

  @override
  int get hashCode => Object.hash(sessionId, role, text);

  @override
  String toString() =>
      'PiChatMessage($role, ${text.length}字${error != null ? ', err' : ''})';
}
