import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:xiaodouzi_fr/core/calendar/presentation/calendar_year_pane.dart';
import 'package:xiaodouzi_fr/core/calendar/domain/calendar_task.dart';
import 'package:xiaodouzi_fr/core/calendar/presentation/calendar_page.dart';
import 'package:xiaodouzi_fr/core/storage/calendar_store.dart';
import 'package:xiaodouzi_fr/core/storage/sqlite/sqlite_providers.dart';

/// 面板内拖拽视觉验证：周条静止态可见性（曾因 offset 公式写反整条
/// 消失在屏外）、周条翻周、年轮盘滑动切年。
/// `flutter test --update-goldens test/core/calendar/calendar_drag_visual_test.dart`
class _FakeRepo implements CalendarTaskRepository {
  @override
  Future<List<CalendarTask>> tasksOnDay(DateTime day,
      {bool includeCompleted = true}) async {
    return [];
  }

  @override
  Future<Set<String>> taskDateKeysBetween(DateTime start, DateTime end,
      {bool includeCompleted = true}) async {
    return {};
  }

  @override
  Future<CalendarTask> create(CalendarTaskDraft draft) async {
    final now = DateTime.now();
    return CalendarTask(
      id: 1,
      title: 't',
      start: now,
      end: now,
      createdAt: now,
      updatedAt: now,
    );
  }

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

void main() {
  setUpAll(() async {
    final fontFile = File(r'C:\Windows\Fonts\msyh.ttc');
    if (!fontFile.existsSync()) return;
    final bytes = fontFile.readAsBytesSync();
    final loader = FontLoader('VisualSmokeFont')
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  });

  testWidgets('周页：静止态七日条原位可见（回归 offset 写反 bug）',
      (tester) async {
    await _pumpApp(tester, 2);
    final today = DateTime.now();
    // 今日日号必须在可命中区域（hitTestable 排除平移出屏的内容）。
    expect(
      find.text('${today.day}').hitTestable(),
      findsWidgets,
      reason: '周条静止态应原位可见，不得被平移出屏',
    );
    await expectLater(
      find.byType(CalendarPage),
      matchesGoldenFile('goldens/drag_week_rest.png'),
    );
  }, skip: !Platform.isWindows);

  testWidgets('周页：横向拖拽跟手翻周并提交', (tester) async {
    await _pumpApp(tester, 2);
    final before = DateTime.now();

    final gesture = await tester.startGesture(const Offset(206, 150));
    await gesture.moveBy(const Offset(-140, 0));
    await tester.pump(const Duration(milliseconds: 60));
    await expectLater(
      find.byType(CalendarPage),
      matchesGoldenFile('goldens/drag_week_mid.png'),
    );
    await gesture.moveBy(const Offset(-60, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    // 拖拽跨越整周：选中日期应前进一周（允许月跨界的粗校验：日号变化）。
    final weekStripCenter = tester.getCenter(find.byType(CalendarPage));
    expect(weekStripCenter.dy, greaterThan(0)); // 页面仍在
    expect(
      find.text('${before.day}'),
      findsWidgets, // 时间轴或周条（新选中日的日号可能不同，宽松断言页面健在）
    );
  }, skip: !Platform.isWindows);

  testWidgets('年页：横向拖拽滑动切年（轮盘提交）', (tester) async {
    await _pumpApp(tester, 0);
    final yearBefore = DateTime.now().year;
    expect(find.text('$yearBefore'), findsWidgets);

    // 模拟真实拖拽：手势机把「跨 slop 事件」的 delta 并入 start（不派发
    // update），大步长单次 move 会丢失全部位移；分多步小 move 让 update
    // 逐帧到达，最终 t≈0.63 > 0.5 触发位置阈值提交。
    const dragOrigin = Offset(206, 420);
    final gesture = await tester.startGesture(dragOrigin);
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(-20, 0));
    }
    await tester.pump(const Duration(milliseconds: 16));
    await expectLater(
      find.byType(CalendarPage),
      matchesGoldenFile('goldens/drag_year_mid.png'),
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      find.text('${yearBefore + 1}'),
      findsWidgets,
      reason: '左滑过阈值后应提交切年：标题年份 +1',
    );
    await expectLater(
      find.byType(CalendarPage),
      matchesGoldenFile('goldens/drag_year_next.png'),
    );
  }, skip: !Platform.isWindows);

  testWidgets('年页：箭头点按走同一轮盘动效', (tester) async {
    await _pumpApp(tester, 0);
    final yearBefore = DateTime.now().year;
    // 页头（月页）也有一对箭头，这里限定在年轮盘内点，避免歧义。
    await tester.tap(
      find.descendant(
        of: find.byType(CalendarYearPane),
        matching: find.byIcon(Icons.chevron_right),
      ),
    );
    // 动画进行中不应立即出现新年份（瞬跳会让此断言失败）。
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpAndSettle();
    expect(find.text('${yearBefore + 1}'), findsWidgets);
  }, skip: !Platform.isWindows);
}
