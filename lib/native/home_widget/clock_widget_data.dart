/// 小组件时钟数据模型
/// 用于与 Android 桌面小组件通信的数据结构
class ClockWidgetData {
  /// 时钟标题
  final String title;

  /// 剩余时间（秒），可为负数（表示已超时）
  final int remainingSeconds;

  /// 总时长（秒）
  final int durationSeconds;

  /// 是否正在运行
  final bool isRunning;

  /// 颜色（Hex 格式）
  final String color;

  /// 格式化的时间字符串 (HH:mm:ss)
  final String formattedTime;

  /// 是否已超时
  final bool isOvertime;

  const ClockWidgetData({
    required this.title,
    required this.remainingSeconds,
    required this.durationSeconds,
    required this.isRunning,
    required this.color,
    required this.formattedTime,
    required this.isOvertime,
  });

  /// 从 LabClock 转换
  factory ClockWidgetData.fromClock({
    required String title,
    required int remainingSeconds,
    required int durationSeconds,
    required bool isRunning,
    required String color,
  }) {
    final isOvertime = remainingSeconds < 0;
    final absSeconds = remainingSeconds.abs();
    final h = absSeconds ~/ 3600;
    final m = (absSeconds % 3600) ~/ 60;
    final s = absSeconds % 60;
    final sign = isOvertime ? '-' : '';

    return ClockWidgetData(
      title: title,
      remainingSeconds: remainingSeconds,
      durationSeconds: durationSeconds,
      isRunning: isRunning,
      color: color,
      formattedTime:
          '$sign${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}',
      isOvertime: isOvertime,
    );
  }

  /// 空数据
  static const empty = ClockWidgetData(
    title: '暂无倒计时',
    remainingSeconds: 0,
    durationSeconds: 0,
    isRunning: false,
    color: '#2196F3',
    formattedTime: '00:00:00',
    isOvertime: false,
  );

  /// 转换为 Map 用于存储
  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'remainingSeconds': remainingSeconds,
      'durationSeconds': durationSeconds,
      'isRunning': isRunning ? 1 : 0,
      'color': color,
      'formattedTime': formattedTime,
      'isOvertime': isOvertime ? 1 : 0,
    };
  }
}
