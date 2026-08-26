/// Clock max 模式的常量（fr todo #27："clock添加一个max模式…"）。
///
/// 自动聚类：按 title 聚合（customTitle ?? clockTitle），每 title 只保留
/// 最长一次已完成记录，作为「个人最佳 BP」展示。
library;

/// Max 模式开关的 UI 文案。
const String kClockMaxModeLabel = 'max 模式';

/// Max 模式副标题：提示用户按标题聚合。
const String kClockMaxModeHint = '按标题聚合 · 显示个人最佳';

/// 最佳记录角标。
const String kClockBestRecordBadge = '个人最佳';

/// 空聚类时的兜底文案（理论上不会出现，仅在用户全删完记录后短暂存在）。
const String kClockMaxModeEmpty = '暂无已完成记录。完成一次即可聚类。';