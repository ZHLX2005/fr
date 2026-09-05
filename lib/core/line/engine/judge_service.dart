import '../domain/constants.dart';

/// 判定结果标签
enum JudgeResultLabel { perfect, great, good, miss }

/// 早晚提示（相对谱面时刻）
enum TimingHint { early, late, none }

/// 判定结果
class JudgeResult {
  final JudgeResultLabel label;
  final String text;
  final int points;
  final double healthChange;
  final double alpha;
  final TimingHint hint;
  final int signedDiffMs;

  const JudgeResult({
    required this.label,
    required this.text,
    required this.points,
    required this.healthChange,
    required this.alpha,
    this.hint = TimingHint.none,
    this.signedDiffMs = 0,
  });
}

/// 判定纯函数
///
/// [signedDiffMs] = clockMs - note.time（负=早，正=晚）。
/// 窗口比较用绝对值；[timingScale] 放大窗口（越宽容越大）。
JudgeResult judge(int signedDiffMs, double timingScale) {
  final timeDiffMs = signedDiffMs.abs();
  final scaledPerfect = (perfectWindow * timingScale).round();
  final scaledGreat = (greatWindow * timingScale).round();
  final scaledGood = (goodWindow * timingScale).round();
  final healthScale = 1.0 / timingScale;

  TimingHint hintFor() {
    if (timeDiffMs <= scaledPerfect) return TimingHint.none;
    if (signedDiffMs < 0) return TimingHint.early;
    if (signedDiffMs > 0) return TimingHint.late;
    return TimingHint.none;
  }

  if (timeDiffMs <= scaledPerfect) {
    return JudgeResult(
      label: JudgeResultLabel.perfect,
      text: 'Perfect',
      points: 3,
      healthChange: 0.05 * healthScale,
      alpha: 0.95,
      signedDiffMs: signedDiffMs,
    );
  }
  if (timeDiffMs <= scaledGreat) {
    return JudgeResult(
      label: JudgeResultLabel.great,
      text: 'Great',
      points: 2,
      healthChange: 0.02 * healthScale,
      alpha: 0.85,
      hint: hintFor(),
      signedDiffMs: signedDiffMs,
    );
  }
  if (timeDiffMs <= scaledGood) {
    return JudgeResult(
      label: JudgeResultLabel.good,
      text: 'Good',
      points: 1,
      healthChange: 0.0,
      alpha: 0.7,
      hint: hintFor(),
      signedDiffMs: signedDiffMs,
    );
  }
  return JudgeResult(
    label: JudgeResultLabel.miss,
    text: 'Miss',
    points: 0,
    healthChange: -0.15 * healthScale,
    alpha: 0.75,
    hint: hintFor(),
    signedDiffMs: signedDiffMs,
  );
}

/// 连击倍率：combo 从 0 起，命中后 combo 增加前用当前 combo 计算。
double comboMultiplier(int comboBeforeHit) {
  final m = 1.0 + comboBeforeHit * comboMultiplierPerHit;
  return m > comboMultiplierMax ? comboMultiplierMax : m;
}
