// test/lab/clock_toggle_latest_test.dart
//
// toggleLatestClock 内部委托给纯函数 resolveToggle；由于 LabClockProvider 构造
// 依赖 Android native（MetronomeService.ensureReady 在 Linux 测试抛
// UnsupportedError），本测试仅覆盖 resolveToggle 纯函数，行为等价。

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/models/lab_clock.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/providers/lab_clock_provider.dart';

LabClock _make({bool isRunning = false, int? remaining, int duration = 60}) =>
    LabClock(
      id: 'c1',
      title: 't',
      createdAt: DateTime(2026),
      durationSeconds: duration,
      remainingSeconds: remaining ?? duration,
      isRunning: isRunning,
    );

void main() {
  group('LabClockProvider.resolveToggle', () {
    test('无 clock（latest == null） → none（toggleLatestClock 无操作）', () {
      expect(LabClockProvider.resolveToggle(null), ToggleAction.none);
    });
    test('运行中 → pause', () {
      expect(
        LabClockProvider.resolveToggle(_make(isRunning: true, remaining: 30)),
        ToggleAction.pause,
      );
    });
    test('等待开始（未启动、remaining == duration）→ start', () {
      expect(
        LabClockProvider.resolveToggle(
          _make(isRunning: false, remaining: 60, duration: 60),
        ),
        ToggleAction.start,
      );
    });
    test('已暂停（remaining < duration）→ start（继续）', () {
      expect(
        LabClockProvider.resolveToggle(
          _make(isRunning: false, remaining: 30, duration: 60),
        ),
        ToggleAction.start,
      );
    });
  });
}