import 'package:flutter/material.dart';

/// 音符类型
enum NoteType { tap, hold, slide }

/// 滑动方向
enum SlideDirection { up, down, left, right }

/// 背景样式
enum BackgroundStyle {
  none,
  grid,
  lines;
}

/// 谱面音符事件
class NoteEvent {
  final int time; // ms，音符到达判定线的时间
  final int column; // 0/1/2
  final NoteType type;
  final SlideDirection? direction; // 仅 slide
  final int? holdDuration; // 仅 hold，ms

  const NoteEvent({
    required this.time,
    required this.column,
    required this.type,
    this.direction,
    this.holdDuration,
  });

  factory NoteEvent.fromJson(Map<String, dynamic> json) {
    return NoteEvent(
      time: json['time'] as int,
      column: json['column'] as int,
      type: NoteType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => NoteType.tap,
      ),
      direction: json['direction'] != null
          ? SlideDirection.values.firstWhere(
              (e) => e.name == json['direction'],
              orElse: () => SlideDirection.up,
            )
          : null,
      holdDuration: json['holdDuration'] as int?,
    );
  }
}

/// 谱面数据
class ChartData {
  final String name;
  final int bpm;
  final int dropDuration;
  final List<NoteEvent> notes;

  const ChartData({
    required this.name,
    required this.bpm,
    required this.dropDuration,
    required this.notes,
  });

  factory ChartData.fromJson(Map<String, dynamic> json) {
    final rawNotes = json['notes'] as List;
    final notes = rawNotes
        .whereType<Map<String, dynamic>>()
        .map((n) => NoteEvent.fromJson(n))
        .toList();
    return ChartData(
      name: json['name'] as String? ?? 'Unnamed',
      bpm: json['bpm'] as int? ?? 120,
      dropDuration: json['dropDuration'] as int? ?? 2500,
      notes: notes,
    );
  }
}

/// 下落中的音符（运行时）
class FallingNote {
  final NoteEvent event;
  final AnimationController controller;
  double currentY;
  bool judged;
  bool removeMe; // 被判定后从绘制层立即移除，只留炸开动画
  bool holding; // 仅 hold：正在被按住
  double holdProgress; // 仅 hold：按住进度 0~1
  int holdJudgeDiff; // 仅 hold：按下时的判定差值（ms），越小越好
  int holdPressTime; // 仅 hold：玩家按下时刻（elapsed）

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
        holdFadeOut = 0.0;
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
