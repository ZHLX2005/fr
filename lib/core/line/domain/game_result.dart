/// 游戏结果数据（不可变）
class GameResult {
  final String songName;
  final String songId;
  final int score;
  final int highScore;
  final int perfectCount;
  final int greatCount;
  final int goodCount;
  final int missCount;
  final int maxCombo;
  final int totalNotes;
  final bool cleared;

  const GameResult({
    required this.songName,
    this.songId = '',
    required this.score,
    required this.highScore,
    required this.perfectCount,
    required this.greatCount,
    required this.goodCount,
    required this.missCount,
    required this.maxCombo,
    required this.totalNotes,
    this.cleared = true,
  });

  /// 准确率 0~100
  double get accuracy {
    if (totalNotes == 0) return 0.0;
    return (perfectCount * 3 + greatCount * 2 + goodCount) /
        (totalNotes * 3) *
        100;
  }

  bool get isFullCombo => missCount == 0 && totalNotes > 0 && cleared;

  bool get isAllPerfect =>
      isFullCombo &&
      greatCount == 0 &&
      goodCount == 0 &&
      perfectCount >= totalNotes;

  /// 等级字母
  String get grade {
    if (isAllPerfect) return 'P';
    final a = accuracy;
    if (a >= 95) return 'S';
    if (a >= 85) return 'A';
    if (a >= 70) return 'B';
    if (a >= 50) return 'C';
    return 'D';
  }

  bool get isNewRecord => score > highScore;

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

  bool get usesGradient => grade == 'P' || grade == 'S';
}
