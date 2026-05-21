import 'dart:math' as math;
import '../domain/constants.dart';
import '../domain/note_event.dart';

// ── 触摸列映射 ──

/// 根据 x 坐标计算所在列
int? columnFromX(double x, double screenWidth, int colCount) {
  final colWidth = screenWidth / colCount;
  for (int i = 0; i < colCount; i++) {
    if (x >= colWidth * i && x < colWidth * (i + 1)) return i;
  }
  return null;
}

/// 检测滑动方向（纯函数）
SlideDirection? swipeDirection(double dx, double dy) {
  const threshold = 100.0;
  if (dx.abs() < threshold && dy.abs() < threshold) return null;
  if (dx.abs() > dy.abs()) {
    return dx > 0 ? SlideDirection.right : SlideDirection.left;
  } else {
    return dy > 0 ? SlideDirection.down : SlideDirection.up;
  }
}

// ── 游戏状态引擎 ──

/// 游戏引擎 — 计分、血量、连击状态机
///
/// 纯 Dart，零 Flutter 依赖。管理分数、血量、连击、判定计数。
class GameEngine {
  int score = 0;
  double health = 1.0;
  int combo = 0;
  int maxCombo = 0;
  int perfectCount = 0;
  int greatCount = 0;
  int goodCount = 0;
  int missCount = 0;

  /// 应用判定结果
  void applyJudge(JudgeResult result) {
    switch (result.label) {
      case JudgeResultLabel.perfect:
        perfectCount++;
        combo++;
      case JudgeResultLabel.great:
        greatCount++;
        combo++;
      case JudgeResultLabel.good:
        goodCount++;
        combo++;
      case JudgeResultLabel.miss:
        break;
    }
    maxCombo = math.max(maxCombo, combo);
    score += result.points;
    health = (health + result.healthChange).clamp(0.0, 1.0);
  }

  /// 应用 Miss（断连击、扣血）
  void applyMiss(double timingScale) {
    missCount++;
    combo = 0;
    final healthScale = 1.0 / timingScale;
    health = (health - 0.15 * healthScale).clamp(0.0, 1.0);
  }

  /// 游戏是否结束
  bool get isGameOver => health <= 0.0;

  /// 重置所有状态
  void reset() {
    score = 0;
    health = 1.0;
    combo = 0;
    maxCombo = 0;
    perfectCount = 0;
    greatCount = 0;
    goodCount = 0;
    missCount = 0;
  }
}
