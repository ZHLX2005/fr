import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/calendar/domain/calendar_task.dart';
import 'package:xiaodouzi_fr/core/calendar/presentation/calendar_page.dart';
import 'package:xiaodouzi_fr/core/storage/calendar_store.dart';
import 'package:xiaodouzi_fr/core/storage/sqlite/sqlite_providers.dart';

/// 日历列表视图：**任务面板浮在日历之上**（参考 Lab 容器下拉面板的层级）。
///
/// 回归点：
///   · 列表视图渲染出面板把手（面板在场，不是上下并列两半屏）；
///   · 点把手面板展开 → FAB 让位（不压在面板内容上）；
///   · 再点收起 → FAB 回来。
class _FakeRepo implements CalendarTaskRepository {
  _FakeRepo() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _tasks = [
      CalendarTask(
        id: 1,
        title: '晨会',
        start: today.add(const Duration(hours: 9)),
        createdAt: now,
        updatedAt: now,
      ),
    ];
  }

  late final List<CalendarTask> _tasks;

  @override
  Future<List<CalendarTask>> tasksOnDay(DateTime day,
          {bool includeCompleted = true}) async =>
      _tasks;

  @override
  Future<Set<String>> taskDateKeysBetween(DateTime start, DateTime end,
          {bool includeCompleted = true}) async =>
      {};

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

Future<void> _pumpCalendar(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sqliteCalendarRepositoryProvider.overrideWithValue(_FakeRepo()),
        sqliteSettingsRepositoryProvider.overrideWithValue(_FakeSettings()),
      ],
      child: const MaterialApp(home: CalendarPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('列表视图：任务面板浮在日历上，把手可展开收起', (tester) async {
    await _pumpCalendar(tester);

    // 面板在场：把手可见。
    final handle = find.byKey(const ValueKey('calendar-panel-handle'));
    expect(handle, findsOneWidget);

    // 收起态：FAB 在（面板还没盖住它）。
    final fab = find.byType(FloatingActionButton);
    expect(fab, findsNothing); // 日历用自定义 FAB 容器，不是 M3 FAB
    expect(find.byIcon(Icons.add), findsOneWidget);

    // 点把手 → 展开：FAB 让位给面板。
    await tester.tap(handle);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add), findsNothing);

    // 再点 → 收起：FAB 回来。
    await tester.tap(handle);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add), findsOneWidget);
  });
}
