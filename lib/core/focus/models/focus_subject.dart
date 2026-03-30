import 'package:flutter/material.dart';

/// 科目模型
class FocusSubject {
  final String id;
  final String name;
  final Color color;
  final int iconIndex; // 在 FocusIcons.availableIcons 中的索引
  final int targetMinutes; // 目标学时（分钟）
  final int completedMinutes; // 已完成学时（分钟）

  FocusSubject({
    required this.id,
    required this.name,
    required this.color,
    required this.iconIndex,
    this.targetMinutes = 0,
    this.completedMinutes = 0,
  });

  /// 获取 IconData
  IconData get icon => FocusIcons.availableIcons[iconIndex % FocusIcons.availableIcons.length];

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
    int? iconIndex,
    int? targetMinutes,
    int? completedMinutes,
  }) {
    return FocusSubject(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      iconIndex: iconIndex ?? this.iconIndex,
      targetMinutes: targetMinutes ?? this.targetMinutes,
      completedMinutes: completedMinutes ?? this.completedMinutes,
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'color': color.toARGB32(),
      'iconIndex': iconIndex,
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
      iconIndex: json['iconIndex'] as int? ?? 0,
      targetMinutes: json['targetMinutes'] as int? ?? 0,
      completedMinutes: json['completedMinutes'] as int? ?? 0,
    );
  }
}

/// 预设科目模板
class FocusSubjectPresets {
  /// 柔和的莫兰迪配色
  static const List<Color> _colors = [
    Color(0xFF8B9DC3), // 灰蓝
    Color(0xFFB5C9A3), // 鼠尾草绿
    Color(0xFFD4B483), // 燕麦色
    Color(0xFFE5989B), // 柔和粉
    Color(0xFFB39EB5), // 淡紫灰
    Color(0xFF9CAF88), // 橄榄绿
  ];

  /// 图标索引列表
  static const List<int> _iconIndices = [0, 1, 2, 3, 4, 5];

  /// 预设名称
  static const List<String> _names = [
    '计算机基础',
    '数学',
    '英语',
    '哲学',
    '阅读',
    '写作',
  ];

  static List<FocusSubject> get presets => List.generate(
        _names.length,
        (i) => FocusSubject(
          id: 'preset_${i + 1}',
          name: _names[i],
          color: _colors[i],
          iconIndex: _iconIndices[i],
          targetMinutes: 3600,
        ),
      );
}

/// 可选的柔和图标列表（常量）
class FocusIcons {
  static const List<IconData> availableIcons = [
    Icons.computer,
    Icons.calculate,
    Icons.menu_book,
    Icons.lightbulb_outline,
    Icons.auto_stories,
    Icons.edit,
    Icons.science,
    Icons.language,
    Icons.history_edu,
    Icons.psychology,
    Icons.music_note,
    Icons.palette,
    Icons.sports_esports,
    Icons.fitness_center,
    Icons.restaurant,
    Icons.travel_explore,
    Icons.camera_alt,
    Icons.code,
    Icons.business,
    Icons.gavel,
  ];
}

/// 可选的柔和颜色列表
class FocusColors {
  static const List<Color> availableColors = [
    Color(0xFF8B9DC3), // 灰蓝
    Color(0xFFB5C9A3), // 鼠尾草绿
    Color(0xFFD4B483), // 燕麦色
    Color(0xFFE5989B), // 柔和粉
    Color(0xFFB39EB5), // 淡紫灰
    Color(0xFF9CAF88), // 橄榄绿
    Color(0xFF88B3C8), // 天蓝
    Color(0xFFC4A484), // 驼色
    Color(0xFFA8D5E2), // 雾蓝
    Color(0xFFE6B89C), // 杏色
    Color(0xFFCDB7B5), // 玫瑰灰
    Color(0xFF9FB4C7), // 蓝灰
  ];
}