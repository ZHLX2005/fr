import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/models/lab_clock.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/providers/lab_clock_provider.dart';

/// [LabClockProvider.tickRemaining] 的纯函数单测。
///
/// 这个函数承载了整个「每秒 tick 不再落盘」改造的正确性：`remainingSeconds`
/// 现在只是派生显示值，重启/回前台一律按 `startTime` + `startRemainingSeconds`
/// 锚点重算。所以锚点的优先级与边界必须锁死。
void main() {
  final t0 = DateTime(2026, 9, 18, 10, 0, 0);

  LabClock clockAt({
    required DateTime startTime,
    int? startRemainingSeconds,
    int? durationSeconds,
    int remainingSeconds = 0,
    bool isRunning = true,
  }) {
    return LabClock(
      id: 'c1',
      title: 't',
      createdAt: startTime,
      isRunning: isRunning,
      remainingSeconds: remainingSeconds,
      startTime: startTime,
      startRemainingSeconds: startRemainingSeconds,
      durationSeconds: durationSeconds,
    );
  }

  group('LabClockProvider.tickRemaining', () {
    test('未运行 → null', () {
      final clock = clockAt(
        startTime: t0,
        startRemainingSeconds: 60,
        isRunning: false,
      );
      expect(LabClockProvider.tickRemaining(clock, t0), isNull);
    });

    test('运行中但 startTime 为 null → null（legacy 脏数据防御）', () {
      final clock = LabClock(
        id: 'c1',
        title: 't',
        createdAt: t0,
        isRunning: true,
        remainingSeconds: 60,
      );
      expect(clock.startTime, isNull);
      expect(LabClockProvider.tickRemaining(clock, t0), isNull);
    });

    test('剩余未变化 → null（不产生无谓的 notify）', () {
      final clock = clockAt(
        startTime: t0,
        startRemainingSeconds: 60,
        remainingSeconds: 60,
      );
      expect(LabClockProvider.tickRemaining(clock, t0), isNull);
    });

    test('锚点优先用 startRemainingSeconds（覆盖陈旧的 remainingSeconds）', () {
      // remainingSeconds 陈旧为 60，锚点说启动时是 100 → 过了 10s 应为 90
      final clock = clockAt(
        startTime: t0,
        startRemainingSeconds: 100,
        durationSeconds: 999,
        remainingSeconds: 60,
      );
      expect(
        LabClockProvider.tickRemaining(clock, t0.add(const Duration(seconds: 10))),
        90,
      );
    });

    test('无 startRemainingSeconds 时回退 durationSeconds', () {
      final clock = clockAt(
        startTime: t0,
        durationSeconds: 300,
        remainingSeconds: 300,
      );
      expect(
        LabClockProvider.tickRemaining(clock, t0.add(const Duration(seconds: 30))),
        270,
      );
    });

    test('两者都无 → 回退 remainingSeconds', () {
      final clock = clockAt(startTime: t0, remainingSeconds: 45);
      expect(
        LabClockProvider.tickRemaining(clock, t0.add(const Duration(seconds: 5))),
        40,
      );
    });

    test('跨过归零返回负值（超时显示依赖它）', () {
      final clock = clockAt(
        startTime: t0,
        startRemainingSeconds: 3,
        remainingSeconds: 3,
      );
      expect(
        LabClockProvider.tickRemaining(clock, t0.add(const Duration(seconds: 5))),
        -2,
      );
    });

    test('长时间后台后一跳到位（不逐秒补）', () {
      final clock = clockAt(
        startTime: t0,
        startRemainingSeconds: 3600,
        remainingSeconds: 3600,
      );
      // 后台 1 小时后回前台
      expect(
        LabClockProvider.tickRemaining(clock, t0.add(const Duration(hours: 1))),
        0,
      );
      // 1 小时零 12 秒
      expect(
        LabClockProvider.tickRemaining(
          clock,
          t0.add(const Duration(hours: 1, seconds: 12)),
        ),
        -12,
      );
    });
  });
}
