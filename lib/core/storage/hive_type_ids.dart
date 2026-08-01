// Hive TypeAdapter typeId 分配表（唯一真相源）
//
// 所有 typed Hive box 的 typeId 必须在此登记，禁止在别处写魔法数字。
// 这样新增 typed model 时能一眼看到哪些 typeId 已被占用，避免冲突。
//
// 分配区段：
// - core 功能: 0-9
// - lab demo:  80-99
//
// 用法：
//   @HiveType(typeId: HiveTypeIds.bodyRecord)   // 模型注解
//   Hive.registerAdapter(BodyRecordAdapter())   // 运行时注册
//   BoxDescriptor(typeId: HiveTypeIds.bodyRecord, ...)  // 面板注册
abstract final class HiveTypeIds {
  // ── core 区段 0-9 ─────────────────────────────
  /// 身体记录
  static const int bodyRecord = 0;

  // ── lab 区段 80-99 ────────────────────────────
  /// 日历事件
  static const int calendarEvent = 90;

  /// 日历人物
  static const int calendarPerson = 91;

  // 新增 typed model 时在此追加，并确认不与已有冲突。
}
