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

  // ===== 圆环参数 =====
  static const double arcStartAngle = 200 * 3.14159265 / 180;
  static const double arcSweepAngle = 140 * 3.14159265 / 180;
  static const double arcStrokeWidth = 20;
  static const double arcHighlightWidth = 10;
  static const int arcVisibleCount = 5;

  // ===== 动画 =====
  static const Duration animDuration = Duration(milliseconds: 300);
  static const Duration buttonPressDuration = Duration(milliseconds: 150);
  static const Duration recordPulseDuration = Duration(milliseconds: 600);

  // ===== 布局 =====
  static const double themeButtonSize = 64;
  static const double themeButtonActiveSize = 88;
  static const double recordButtonSize = 120;

  // ===== 颜色 =====
  static const Color bgColor = Color(0xFFF8F9FA);
  static const Color cardBg = Colors.white;
  static const Color textPrimary = Color(0xFF2D3436);
  static const Color textSecondary = Color(0xFF636E72);
  static const Color textMuted = Color(0xFFB2BEC3);
  static const Color shadowColor = Color(0x1A000000);
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
