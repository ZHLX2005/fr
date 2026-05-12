/// 笔记编辑器模块常量
class NoteConstants {
  NoteConstants._();

  /// 模块名称
  static const String moduleName = 'note';

  /// 默认 AI 上下文最大字符数
  static const int defaultContextMaxChars = 800;

  /// 双击空格触发间隔 (ms)
  static const int doubleSpaceInterval = 280;

  /// 空格状态重置超时 (ms)
  static const int spaceResetTimeout = 350;

  /// AI 生成超时时间 (ms)
  static const int aiRequestTimeout = 30000;

  /// 默认 AI 模型
  static const String defaultAiModel = 'gpt-4.1-mini';

  /// 默认 AI 温度
  static const double defaultAiTemperature = 0.4;
}
