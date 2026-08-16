import '../interfaces/message_data.dart';

/// 系统消息数据 —— 后台事件的可视化卡片。
///
/// 与业务交互卡（ask/selection）不同，系统消息是只读信息流：
///   - 时间：事件发生时刻（本地时区）
///   - 事件类型：稳定字符串字面量（auto_apk_check_started /
///     auto_apk_download_completed / ...），用于图标/颜色映射
///   - 标题：单行概要
///   - 详情：可选多行说明
///
/// 设计原则：
///   - 数据层只描述事件，不耦合渲染（策略 widget 决定图标/配色）
///   - eventType 用字符串字面量，后续要加新事件只需在策略 switch 加分支，
///     不需要新建 data 类
class SystemEventMessageData implements IMessageData {
  /// 本地时区显示用时间（"2026-08-16T22:30" 形式）
  final String time;

  /// 事件类型字面量，例如 'auto_apk_check_started'
  final String eventType;

  /// 单行标题
  final String title;

  /// 可选详情（多行）
  final String? detail;

  const SystemEventMessageData({
    required this.time,
    required this.eventType,
    required this.title,
    this.detail,
  });

  @override
  String get type => 'system-event';
}