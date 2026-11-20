import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/calendar/domain/calendar_task.dart';
import 'package:xiaodouzi_fr/core/calendar/presentation/calendar_page.dart';
import 'package:xiaodouzi_fr/core/storage/calendar_store.dart';
import 'package:xiaodouzi_fr/core/storage/sqlite/sqlite_providers.dart';

/// 视觉冒烟：把月视图渲染成 golden PNG（--update-goldens 生成），
/// 用于与 docs/prototypes/calendar-capsule-nav.html 对照验收。
class _FakeRepo implements CalendarTaskRepository {
  _FakeRepo() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    _tasks = [
      CalendarTask(
        id: 1,
        title: '晨会',
        start: today.add(const Duration(hours: 9)),
        end: today.add(const Duration(hours: 10)),
        createdAt: now,
        updatedAt: now,
      ),
      CalendarTask(
        id: 2,
        title: '团队周会',
        start: today.add(const Duration(hours: 10, minutes: 30)),
        end: today.add(const Duration(hours: 11, minutes: 30)),
        createdAt: now,
        updatedAt: now,
      ),
      CalendarTask(
        id: 3,
        title: '竹林散步',
        start: today.add(const Duration(hours: 14)),
        end: today.add(const Duration(hours: 15)),
        createdAt: now,
        updatedAt: now,
      ),
      CalendarTask(
        id: 4,
        title: '晚间复盘',
        start: tomorrow.add(const Duration(hours: 21, minutes: 30)),
        end: tomorrow.add(const Duration(hours: 22)),
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

Future<void> _pump(WidgetTester tester, int tab, String golden) async {
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
  await expectLater(
    find.byType(CalendarPage),
    matchesGoldenFile('goldens/$golden'),
  );
}

void main() {
  setUpAll(() async {
    // 测试默认 Ahem 字体会把中文渲染成方块；加载系统微软雅黑以保证
    // golden 与真机视觉一致。Windows-only（本项目冒烟跑在 Windows 上）。
    final fontFile = File(r'C:\Windows\Fonts\msyh.ttc');
    if (!fontFile.existsSync()) return;
    final bytes = fontFile.readAsBytesSync();
    final loader = FontLoader('VisualSmokeFont')
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  });

  testWidgets('golden：月视图（默认页签）', (tester) async {
    await _pump(tester, 1, 'month.png');
  }, skip: !Platform.isWindows);

  testWidgets('golden：年视图', (tester) async {
    await _pump(tester, 0, 'year.png');
  }, skip: !Platform.isWindows);

  testWidgets('golden：日程视图', (tester) async {
    await _pump(tester, 4, 'agenda.png');
  }, skip: !Platform.isWindows);
}
