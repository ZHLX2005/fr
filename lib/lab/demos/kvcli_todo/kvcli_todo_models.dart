// KV 清单 —— 数据模型。
//
// KvTask 存于 todo:open / todo:done / todo:freeze（Task[] JSON 快照），
// 快捷 topic（tag）存于 todo:topics（String[] JSON 快照）。
// KV 只提供快照存储；模型层只做 JSON 编解码，不掺业务。

import 'dart:convert';

/// 清单任务。doneAt/note 在待办阶段为空串；frozenAt 在冻结阶段之外为空串；
/// topic 为任务主题（路由维度）。
class KvTask {
  const KvTask({
    required this.id,
    required this.topic,
    required this.text,
    required this.createdAt,
    this.doneAt = '',
    this.note = '',
    this.frozenAt = '',
  });

  final int id;
  final String topic;
  final String text;
  final String createdAt;
  final String doneAt;
  final String note;
  final String frozenAt;

  /// 标记完成：补 doneAt + note，其余字段不变。
  KvTask copyWith({String? doneAt, String? note}) => KvTask(
        id: id,
        topic: topic,
        text: text,
        createdAt: createdAt,
        doneAt: doneAt ?? this.doneAt,
        note: note ?? this.note,
        frozenAt: frozenAt,
      );

  /// 编辑后保留 id/createdAt/doneAt/frozenAt，替换 topic/text/note。
  KvTask edited({
    required String topic,
    required String text,
    required String note,
  }) =>
      KvTask(
        id: id,
        topic: topic,
        text: text,
        createdAt: createdAt,
        doneAt: doneAt,
        note: note,
        frozenAt: frozenAt,
      );

  /// 冻结：补 frozenAt，其余字段不变（id 保留，待解冻时再校验冲突）。
  KvTask frozen(String at) => KvTask(
        id: id,
        topic: topic,
        text: text,
        createdAt: createdAt,
        doneAt: doneAt,
        note: note,
        frozenAt: at,
      );

  /// 解冻：清 frozenAt；id 撞现有待办时用 [newId] 换新，其余字段保留。
  KvTask unfrozen({int? newId}) => KvTask(
        id: newId ?? id,
        topic: topic,
        text: text,
        createdAt: createdAt,
        doneAt: doneAt,
        note: note,
        frozenAt: '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'topic': topic,
        'text': text,
        'createdAt': createdAt,
        'doneAt': doneAt,
        'note': note,
        'frozenAt': frozenAt,
      };

  static KvTask fromJson(Map<String, dynamic> j) => KvTask(
        id: (j['id'] as num).toInt(),
        topic: j['topic'] as String? ?? '',
        text: j['text'] as String? ?? '',
        createdAt: j['createdAt'] as String? ?? '',
        doneAt: j['doneAt'] as String? ?? '',
        note: j['note'] as String? ?? '',
        frozenAt: j['frozenAt'] as String? ?? '',
      );

  /// 从快照 JSON 解析任务数组；空串 / 解析失败返回空列表（不阻塞 UI）。
  static List<KvTask> parseList(String raw) {
    if (raw.trim().isEmpty) return const [];
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return list.map(KvTask.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }
}
