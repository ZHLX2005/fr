import '../domain/constants.dart';

/// 判定结果标签
enum JudgeResultLabel { perfect, great, good, miss }

/// 判定结果
class JudgeResult {
  final JudgeResultLabel label;
  final String text;
  final int points;
  final double healthChange;
  final double alpha;

  const JudgeResult({
    required this.label,
    required this.text,
    required this.points,
    required this.healthChange,
    required this.alpha,
  });
}

/// 判定纯函数
///
/// 输入时间差（ms）和判定缩放，输出判定结果。
/// 不依赖任何 Flutter 类型，可单元测试。
JudgeResult judge(int timeDiffMs, double timingScale) {
  final scaledPerfect = (perfectWindow * timingScale).round();
  final scaledGreat = (greatWindow * timingScale).round();
  final scaledGood = (goodWindow * timingScale).round();
  final healthScale = 1.0 / timingScale;

  if (timeDiffMs <= scaledPerfect) {
    return JudgeResult(
      label: JudgeResultLabel.perfect,
      text: 'Perfect',
      points: 3,
      healthChange: 0.05 * healthScale,
      alpha: 0.6,
    );
  } else if (timeDiffMs <= scaledGreat) {
    return JudgeResult(
      label: JudgeResultLabel.great,
      text: 'Great',
      points: 2,
      healthChange: 0.02 * healthScale,
      alpha: 0.4,
    );
  } else if (timeDiffMs <= scaledGood) {
    return JudgeResult(
      label: JudgeResultLabel.good,
      text: 'Good',
      points: 1,
      healthChange: 0.0,
      alpha: 0.25,
    );
  } else {
    return JudgeResult(
      label: JudgeResultLabel.miss,
      text: 'Good',
      points: 1,
      healthChange: 0.0,
      alpha: 0.25,
    );
  }
}
