import 'package:flutter/material.dart';

/// 下落中的圆圈
class FallingCircle {
  final AnimationController controller;
  double currentY;
  bool exploded;
  bool missed;

  FallingCircle({
    required this.controller,
    required this.currentY,
  })  : exploded = false,
        missed = false;
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

/// 粒子数据
class Particle {
  final double angle;
  final double distance;
  final double initialAlpha;

  const Particle({
    required this.angle,
    required this.distance,
    required this.initialAlpha,
  });
}
