// kvcli_todo_demo 模块常量
//
// KV 只提供快照存储：每个实体 = 一把 key 的 JSON 快照。
// task 完整 CRUD；tag(topic) 仅添加+删除；prompt 不做。

/// KV 清单模块常量
class KvCliTodoConst {
  KvCliTodoConst._();

  /// 待办任务快照 key（Task[] JSON）
  static const String keyOpen = 'todo:open';

  /// 已完成任务快照 key（Task[] JSON）
  static const String keyDone = 'todo:done';

  /// 快捷 topic（tag）快照 key（String[] JSON）
  static const String keyTopics = 'todo:topics';

  /// 冷数据 key 前缀（已完成清理归档；app 只写不查）
  static const String keyDoneColdPrefix = 'todo:done:cold:';

  /// 按日期分片的冷数据 key，避免同前缀被覆盖。
  static String coldKeyFor(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '$keyDoneColdPrefix${d.year}-${two(d.month)}-${two(d.day)}';
  }
}
