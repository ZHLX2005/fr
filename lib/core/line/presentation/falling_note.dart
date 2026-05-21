import 'package:flutter/material.dart';
import '../domain/note_event.dart';
import '../domain/particle.dart';

/// 下落中的音符（运行时，含 AnimationController）
class FallingNote {
  final NoteEvent event;
  final AnimationController controller;
  double currentY;
  int spawnElapsed;
  bool judged;
  bool removeMe;
  bool holding;
  double holdProgress;
  int holdJudgeDiff;
  int holdPressTime;
  double holdFadeOut;

  FallingNote({
    required this.event,
    required this.controller,
    required this.currentY,
  })  : judged = false,
        removeMe = false,
        holding = false,
        holdProgress = 0.0,
        holdJudgeDiff = 0,
        holdPressTime = 0,
        holdFadeOut = 0.0,
        spawnElapsed = 0;
}

/// 炸开动画状态
class ExplodeAnimation {
  final AnimationController controller;
  final double x;
  final double y;
  final List<Particle> particles;
  final double radius;

  ExplodeAnimation({
    required this.controller,
    required this.x,
    required this.y,
    required this.particles,
    required this.radius,
  });
}

/// 判定文字反馈
class JudgeFeedback {
  final String text;
  final double x;
  final double y;
  final Color color;
  final double baseAlpha;
  final AnimationController controller;

  JudgeFeedback({
    required this.text,
    required this.x,
    required this.y,
    required this.color,
    required this.baseAlpha,
    required this.controller,
  });
}
