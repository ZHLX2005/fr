import 'dart:math' as math;
import 'judge_service.dart';

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

  /// 应用判定结果（命中或窗口内 miss 字样）
  void applyJudge(JudgeResult result) {
    switch (result.label) {
      case JudgeResultLabel.perfect:
        perfectCount++;
        final mult = comboMultiplier(combo);
        combo++;
        score += (result.points * mult).round();
        health = (health + result.healthChange).clamp(0.0, 1.0);
      case JudgeResultLabel.great:
        greatCount++;
        final mult = comboMultiplier(combo);
        combo++;
        score += (result.points * mult).round();
        health = (health + result.healthChange).clamp(0.0, 1.0);
      case JudgeResultLabel.good:
        goodCount++;
        final mult = comboMultiplier(combo);
        combo++;
        score += (result.points * mult).round();
        health = (health + result.healthChange).clamp(0.0, 1.0);
      case JudgeResultLabel.miss:
        // 窗口内「按下但太偏」也走 miss：断连击 + 扣血，不加分
        applyMissHealth(result.healthChange.abs());
    }
    maxCombo = math.max(maxCombo, combo);
  }

  /// 超时 Miss（断连击、扣血）
  void applyMiss(double timingScale) {
    final healthScale = 1.0 / timingScale;
    applyMissHealth(0.15 * healthScale);
  }

  void applyMissHealth(double amount) {
    missCount++;
    combo = 0;
    health = (health - amount).clamp(0.0, 1.0);
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
