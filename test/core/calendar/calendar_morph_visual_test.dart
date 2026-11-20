import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/calendar/domain/calendar_task.dart';
import 'package:xiaodouzi_fr/core/calendar/presentation/calendar_page.dart';
import 'package:xiaodouzi_fr/core/storage/calendar_store.dart';
import 'package:xiaodouzi_fr/core/storage/sqlite/sqlite_providers.dart';

/// 容器变换（年⇄月 morph）中间帧视觉验证：与原型逐帧对照手感。
/// `flutter test --update-goldens test/core/calendar/calendar_morph_visual_test.dart`
class _FakeRepo implements CalendarTaskRepository {
  _FakeRepo() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _tasks = [
      CalendarTask(
        id: 1,
        title: '晨会',
        start: today.add(const Duration(hours: 9)),
        end: today.add(const Duration(hours: 10)),
        createdAt: now,
        updatedAt: now,
      ),
    ];
  }

  late List<CalendarTask> _tasks;

  @override
  Future<List<CalendarTask>> tasksOnDay(DateTime day,
      {bool includeCompleted = true}) async {
    final dayOnly = DateTime(day.year, day.month, day.day);
    final tomorrow = dayOnly.add(const Duration(days: 1));
    return _tasks
        .where((t) =>
            !t.start.isBefore(dayOnly) && t.start.isBefore(tomorrow))
        .toList();
  }

  @override
  Future<Set<String>> taskDateKeysBetween(DateTime start, DateTime end,
      {bool includeCompleted = true}) async {
    return {};
  }

  @override
  Future<CalendarTask> create(CalendarTaskDraft draft) async => _tasks.first;

  @override
  Future<void> update(CalendarTask task) async {}

  @override
  Future<void> toggleCompleted(CalendarTask task) async {}

  @override
  Future<void> delete(int id) async {}
}

class _FakeSettings implements KeyValueRepository {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<void> remove(String key) async {}
}

Future<void> _pumpApp(WidgetTester tester, int tab) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sqliteCalendarRepositoryProvider.overrideWithValue(_FakeRepo()),
        sqliteSettingsRepositoryProvider.overrideWithValue(_FakeSettings()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6B7F82),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          fontFamily: 'VisualSmokeFont',
        ),
        home: CalendarPage(initialTab: tab),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// morph 是 520ms 定长动画。注意 Ticker 首次 tick 上报 0 elapsed：
/// pump() 布局并在帧尾 postFrame 启动 forward；下一次 pump 首帧 t=0，
/// 之后每 pump 140ms 采样一次（0 → 0.27 → 0.54 → settle 终态）。
Future<void> _captureFrames(
  WidgetTester tester,
  String prefix,
) async {
  await tester.pump(); // 帧 A：setState + postFrame 启动控制器
  await tester.pump(const Duration(milliseconds: 140)); // t = 0
  await tester.pump(const Duration(milliseconds: 140)); // t ≈ 0.27
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/${prefix}_27.png'),
  );
  await tester.pump(const Duration(milliseconds: 140)); // t ≈ 0.54
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/${prefix}_54.png'),
  );
  await tester.pumpAndSettle();
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/${prefix}_end.png'),
  );
}

void main() {
  setUpAll(() async {
    final fontFile = File(r'C:\Windows\Fonts\msyh.ttc');
    if (!fontFile.existsSync()) return;
    final bytes = fontFile.readAsBytesSync();
    final loader = FontLoader('VisualSmokeFont')
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  });

  testWidgets('morph 中间帧：月 → 年（胶囊点「年」）', (tester) async {
    await _pumpApp(tester, 1);
    await tester.tap(find.text('年'));
    await _captureFrames(tester, 'morph_m2y');
  }, skip: !Platform.isWindows);

  testWidgets('morph 中间帧：年 → 月（点卡片放大）', (tester) async {
    await _pumpApp(tester, 0);
    // 当前可视月的卡片（今日所在月）。
    final monthLabel =
        DateTime.now().month; // 今日月，卡片 label「N月」
    await tester.tap(find.text('$monthLabel月'));
    await _captureFrames(tester, 'morph_y2m');
  }, skip: !Platform.isWindows);
}
