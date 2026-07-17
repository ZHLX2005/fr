import 'package:flutter/material.dart';

/// 节拍器常量定义
/// 包含节拍模式、重音类型、默认参数等常量

/// 预置节拍模式
class MetronomePresets {
  MetronomePresets._();

  /// 常见节拍模式：[名称, 每小节拍数, 重音拍索引列表]
  static const List<BeatPattern> patterns = [
    BeatPattern(name: '4/4', beatsPerMeasure: 4, accentIndices: {0}),
    BeatPattern(name: '3/4', beatsPerMeasure: 3, accentIndices: {0}),
    BeatPattern(name: '2/4', beatsPerMeasure: 2, accentIndices: {0}),
    BeatPattern(name: '6/8', beatsPerMeasure: 6, accentIndices: {0, 3}),
    BeatPattern(name: '5/4', beatsPerMeasure: 5, accentIndices: {0, 2}),
    BeatPattern(name: '7/8', beatsPerMeasure: 7, accentIndices: {0, 3, 5}),
    BeatPattern(name: '9/8', beatsPerMeasure: 9, accentIndices: {0, 3, 6}),
  ];

  /// 获取默认模式
  static BeatPattern get defaultPattern => patterns.first;
}

/// 节拍模式定义
class BeatPattern {
  const BeatPattern({
    required this.name,
    required this.beatsPerMeasure,
    required this.accentIndices,
  });

  final String name;
  final int beatsPerMeasure;
  final Set<int> accentIndices;

  /// 获取第 N 拍的重音级别
  AccentLevel getAccentLevel(int beatIndex) {
    if (accentIndices.contains(beatIndex)) {
      return AccentLevel.accent; // 强拍
    }
    // 检查是否为次强拍（通常是偶数拍但不在重音列表中）
    if (beatIndex == 2 && !accentIndices.contains(2)) {
      return AccentLevel.medium;
    }
    return AccentLevel.weak; // 弱拍
  }
}

/// 重音级别
enum AccentLevel {
  accent,  // 强拍（重音）- 最大音量
  medium,  // 次强拍 - 中等音量
  weak,    // 弱拍 - 最小音量
}

/// 重音级别对应的音量
class AccentVolume {
  AccentVolume._();

  static const Map<AccentLevel, double> volumeMap = {
    AccentLevel.accent: 0.9,
    AccentLevel.medium: 0.6,
    AccentLevel.weak: 0.35,
  };

  /// 获取指定重音级别的音量
  static double getVolume(AccentLevel level) {
    return volumeMap[level] ?? 0.5;
  }
}

/// 重音级别对应的频率
class AccentFrequency {
  AccentFrequency._();

  static const Map<AccentLevel, double> frequencyMap = {
    AccentLevel.accent: 1000.0, // 强拍 - 高频，更清脆
    AccentLevel.medium: 800.0,  // 次强拍 - 中频
    AccentLevel.weak: 600.0,    // 弱拍 - 低频
  };

  static double getFrequency(AccentLevel level) {
    return frequencyMap[level] ?? 800.0;
  }
}

/// 重音级别对应的颜色（用于 UI 显示）
class AccentColor {
  AccentColor._();

  static const Map<AccentLevel, Color> colorMap = {
    AccentLevel.accent: Color(0xFFE53935), // 红色 - 强拍
    AccentLevel.medium: Color(0xFFFFA726), // 橙色 - 次强拍
    AccentLevel.weak: Color(0xFF66BB6A),   // 绿色 - 弱拍
  };

  static Color getColor(AccentLevel level) {
    return colorMap[level] ?? Colors.grey;
  }
}

/// 节拍器默认参数
class MetronomeDefaults {
  MetronomeDefaults._();

  /// 默认 BPM
  static const int defaultBpm = 120;

  /// BPM 范围
  static const int minBpm = 20;
  static const int maxBpm = 300;

  /// 默认拍号
  static const int defaultBeatsPerMeasure = 4;

  /// 音频参数
  static const int sampleRate = 44100;

  /// 节拍音持续时间（秒）
  static const double clickDurationSec = 0.05;

  /// 缓冲区时长（秒）- 生成足够长的时间以循环播放
  static const double bufferDurationSec = 4.0;

  /// Tap Tempo 参数
  static const int tapTempoHistorySize = 4;
  static const int tapTempoMinIntervalMs = 300;
  static const int tapTempoMaxIntervalMs = 3000;
}

/// 节拍器类型（用于不同场景）
enum MetronomeType {
  practice,    // 练习模式
  performance, // 演出模式
  teaching,    // 教学模式
}
