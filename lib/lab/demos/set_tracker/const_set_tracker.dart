import 'package:flutter/material.dart';

/// 训练组追踪器常量
class SetTrackerConst {
  SetTrackerConst._();

  // ===== 训练主题 =====
  static const List<WorkoutTheme> themes = [
    WorkoutTheme(
      id: 'chest',
      label: '胸肌',
      gradient: [Color(0xFFFF6B6B), Color(0xFFFF8E53)],
      icon: Icons.fitness_center,
    ),
    WorkoutTheme(
      id: 'back',
      label: '背部',
      gradient: [Color(0xFF4ECDC4), Color(0xFF44A08D)],
      icon: Icons.accessibility_new,
    ),
    WorkoutTheme(
      id: 'legs',
      label: '腿部',
      gradient: [Color(0xFFA8E6CF), Color(0xFF1EAE98)],
      icon: Icons.directions_run,
    ),
    WorkoutTheme(
      id: 'shoulders',
      label: '肩部',
      gradient: [Color(0xFFFFD93D), Color(0xFFF6AD55)],
      icon: Icons.person,
    ),
    WorkoutTheme(
      id: 'arms',
      label: '手臂',
      gradient: [Color(0xFF6C5CE7), Color(0xFFA29BFE)],
      icon: Icons.sports_martial_arts,
    ),
    WorkoutTheme(
      id: 'core',
      label: '核心',
      gradient: [Color(0xFFFD79A8), Color(0xFFFDCB6E)],
      icon: Icons.self_improvement,
    ),
  ];

  // ===== 数值选项（次数）=====
  static const List<String> repsValues = [
    '5', '6', '8', '10', '12', '15', '20', '25', '30'
  ];

  // ===== 上弧线：圆心锚在区域顶部外侧，向下拱，真正的半圆 =====
  static const double topArcStartAngle = 15 * 3.14159265 / 180;
  static const double topArcSweepAngle = 150 * 3.14159265 / 180;
  static const double topArcLift = 32;

  // ===== 下弧线：圆心锚在区域底部外侧，向上拱，真正的半圆 =====
  static const double bottomArcStartAngle = 195 * 3.14159265 / 180;
  static const double bottomArcSweepAngle = 150 * 3.14159265 / 180;
  static const double bottomArcLift = 32;

  // ===== 圆环通用参数 =====
  static const double arcRadiusFactor = 0.95;
  static const double arcStrokeWidth = 20;
  static const double arcHighlightWidth = 12;
  static const int arcVisibleCount = 5;

  // ===== 动画 =====
  static const Duration animDuration = Duration(milliseconds: 300);
  static const Duration buttonPressDuration = Duration(milliseconds: 150);

  // ===== 布局 =====
  static const double recordButtonSize = 100;

  // ===== 颜色 =====
  static const Color bgColor = Color(0xFFF8F9FA);
  static const Color cardBg = Colors.white;
  static const Color textPrimary = Color(0xFF2D3436);
  static const Color textSecondary = Color(0xFF636E72);
  static const Color textMuted = Color(0xFFB2BEC3);
  static const Color shadowColor = Color(0x1A000000);
  static const Color trackBaseColor = Color(0xFFE8E8EC);
}

/// 训练主题数据
class WorkoutTheme {
  final String id;
  final String label;
  final List<Color> gradient;
  final IconData icon;

  const WorkoutTheme({
    required this.id,
    required this.label,
    required this.gradient,
    required this.icon,
  });

  LinearGradient get linearGradient => LinearGradient(
        colors: gradient,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
}
