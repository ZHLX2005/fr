import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/line/engine/game_engine.dart';
import 'package:xiaodouzi_fr/core/line/engine/judge_service.dart';

void main() {
  group('judge', () {
    test('perfect / great / good windows', () {
      expect(judge(0, 1).label, JudgeResultLabel.perfect);
      expect(judge(50, 1).label, JudgeResultLabel.perfect);
      expect(judge(51, 1).label, JudgeResultLabel.great);
      expect(judge(100, 1).label, JudgeResultLabel.great);
      expect(judge(101, 1).label, JudgeResultLabel.good);
      expect(judge(150, 1).label, JudgeResultLabel.good);
    });

    test('outside good is Miss with zero points', () {
      final r = judge(151, 1);
      expect(r.label, JudgeResultLabel.miss);
      expect(r.text, 'Miss');
      expect(r.points, 0);
      expect(r.healthChange, lessThan(0));
    });

    test('early / late hints', () {
      expect(judge(-80, 1).hint, TimingHint.early);
      expect(judge(80, 1).hint, TimingHint.late);
      expect(judge(0, 1).hint, TimingHint.none);
    });
  });

  group('GameEngine', () {
    test('combo multiplies score and miss resets combo', () {
      final e = GameEngine();
      e.applyJudge(judge(0, 1)); // perfect, combo 0 → 3
      expect(e.score, 3);
      expect(e.combo, 1);
      e.applyJudge(judge(0, 1)); // perfect, combo 1 → 3 * 1.02
      expect(e.score, 3 + (3 * 1.02).round());
      e.applyMiss(1.0);
      expect(e.combo, 0);
      expect(e.missCount, 1);
    });
  });
}
