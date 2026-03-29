import 'package:flutter/material.dart';

/// 科目模型
class FocusSubject {
  final String id;
  final String name;
  final Color color;
  final String icon;
  final int targetMinutes; // 目标学时（分钟）
  final int completedMinutes; // 已完成学时（分钟）

  FocusSubject({
    required this.id,
    required this.name,
    required this.color,
    required this.icon,
    this.targetMinutes = 0,
    this.completedMinutes = 0,
  });

  /// 完成进度百分比
  double get progress {
    if (targetMinutes == 0) return 0;
    return (completedMinutes / targetMinutes).clamp(0.0, 1.0);
  }

  /// 剩余学时
  int get remainingMinutes => (targetMinutes - completedMinutes).clamp(0, targetMinutes);

  FocusSubject copyWith({
    String? id,
    String? name,
    Color? color,
    String? icon,
    int? targetMinutes,
    int? completedMinutes,
  }) {
    return FocusSubject(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      targetMinutes: targetMinutes ?? this.targetMinutes,
      completedMinutes: completedMinutes ?? this.completedMinutes,
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'color': color.value,
      'icon': icon,
      'targetMinutes': targetMinutes,
      'completedMinutes': completedMinutes,
    };
  }

  /// 从JSON转换
  factory FocusSubject.fromJson(Map<String, dynamic> json) {
    return FocusSubject(
      id: json['id'] as String,
      name: json['name'] as String,
      color: Color(json['color'] as int),
      icon: json['icon'] as String,
      targetMinutes: json['targetMinutes'] as int? ?? 0,
      completedMinutes: json['completedMinutes'] as int? ?? 0,
    );
  }
}

/// 预设科目模板
class FocusSubjectPresets {
  static List<FocusSubject> get presets => [
    FocusSubject(
      id: 'preset_1',
      name: '计算机基础',
      color: Color(0xFF5C9EAD), // 莫兰迪蓝
      icon: '💻',
      targetMinutes: 3600, // 60小时
    ),
    FocusSubject(
      id: 'preset_2',
      name: '数学',
      color: Color(0xFF88B3C8), // 柔和天蓝
      icon: '📐',
      targetMinutes: 3600,
    ),
    FocusSubject(
      id: 'preset_3',
      name: '英语',
      color: Color(0xFFB5A89F), // 淡紫
      icon: '📚',
      targetMinutes: 3600,
    ),
    FocusSubject(
      id: 'preset_4',
      name: '哲学',
      color: Color(0xFF9CAF88), // 鼠尾草绿
      icon: '🤔',
      targetMinutes: 1800,
    ),
    FocusSubject(
      id: 'preset_5',
      name: '阅读',
      color: Color(0xFFD4B483), // 燕麦色
      icon: '📖',
      targetMinutes: 1800,
    ),
    FocusSubject(
      id: 'preset_6',
      name: '写作',
      color: Color(0xFFE5989B), // 柔和粉
      icon: '✍️',
      targetMinutes: 1800,
    ),
  ];
}
