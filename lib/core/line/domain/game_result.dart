/// 游戏结果数据（不可变）
class GameResult {
  final String songName;
  final int score;
  final int highScore;
  final int perfectCount;
  final int greatCount;
  final int goodCount;
  final int missCount;
  final int maxCombo;
  final int totalNotes;

  const GameResult({
    required this.songName,
    required this.score,
    required this.highScore,
    required this.perfectCount,
    required this.greatCount,
    required this.goodCount,
    required this.missCount,
    required this.maxCombo,
    required this.totalNotes,
  });

  /// 准确率 0~100
  double get accuracy {
    if (totalNotes == 0) return 0.0;
    return (perfectCount * 3 + greatCount * 2 + goodCount) /
        (totalNotes * 3) *
        100;
  }

  /// 等级字母
  String get grade {
    final a = accuracy;
    if (a >= 100) return 'P';
    if (a >= 95) return 'S';
    if (a >= 85) return 'A';
    if (a >= 70) return 'B';
    if (a >= 50) return 'C';
    return 'D';
  }

  /// 是否新纪录
  bool get isNewRecord => score > highScore;

  /// 等级对应 ARGB 色值
  int get gradeArgb {
    switch (grade) {
      case 'P':
        return 0xFFc44dff;
      case 'S':
        return 0xFFffd700;
      case 'A':
        return 0xFF4fc3f7;
      case 'B':
        return 0xFF81c784;
      case 'C':
        return 0xFFffb74d;
      default:
        return 0xFFe57373;
    }
  }

  /// 是否使用渐变（仅 P 和 S）
  bool get usesGradient => grade == 'P' || grade == 'S';
}
