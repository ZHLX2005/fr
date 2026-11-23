import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/calendar/domain/calendar_task.dart';
import 'package:xiaodouzi_fr/core/calendar/presentation/calendar_capsule_nav.dart';
import 'package:xiaodouzi_fr/core/calendar/presentation/calendar_month_pane.dart';
import 'package:xiaodouzi_fr/core/calendar/presentation/calendar_page.dart';
import 'package:xiaodouzi_fr/core/calendar/presentation/calendar_schedule_panes.dart';
import 'package:xiaodouzi_fr/core/storage/calendar_store.dart';
import 'package:xiaodouzi_fr/core/storage/sqlite/sqlite_providers.dart';

/// 胶囊日历页回归（重构自 docs/prototypes/calendar-capsule-nav.html）：
///
///   · 五页签胶囊在场，月为默认页签；
///   · 切「日程」→ 日程分组（今天/明天）与任务卡渲染；
///   · 切「日」→ 时间轴事件块渲染；
///   · 月页收展抓手：抓手在场（月历+面板双态的固有件）；
///   · 任务勾选切换完成态（fake repo 状态联动）。
class _FakeRepo implements CalendarTaskRepository {
  _FakeRepo({List<CalendarTask> extra = const []}) {
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
        start: today.add(const Duration(hours: 10)),
        end: today.add(const Duration(hours: 11)),
        createdAt: now,
        updatedAt: now,
      ),
      CalendarTask(
        id: 3,
        title: '竹林散步',
        start: tomorrow.add(const Duration(hours: 14)),
        end: tomorrow.add(const Duration(hours: 15)),
        createdAt: now,
        updatedAt: now,
      ),
      ...extra,
    ];
  }

  late List<CalendarTask> _tasks;
  bool _toggled = false;

  @override
  Future<List<CalendarTask>> tasksOnDay(
    DateTime day, {
    bool includeCompleted = true,
  }) async {
    final dayOnly = DateTime(day.year, day.month, day.day);
    final tomorrow = dayOnly.add(const Duration(days: 1));
    return _tasks
        .where((t) => !t.start.isBefore(dayOnly) && t.start.isBefore(tomorrow))
        .toList();
  }

  @override
  Future<Set<String>> taskDateKeysBetween(
    DateTime start,
    DateTime end, {
    bool includeCompleted = true,
  }) async {
    return {};
  }

  @override
  Future<CalendarTask> create(CalendarTaskDraft draft) async => _tasks.first;

  @override
  Future<void> update(CalendarTask task) async {
    _tasks = [for (final t in _tasks) t.id == task.id ? task : t];
  }

  @override
  Future<void> toggleCompleted(CalendarTask task) async {
    _toggled = !_toggled;
    final updated = task.copyWith(
      completedAt: _toggled ? DateTime.now() : null,
      clearCompletedAt: !_toggled,
    );
    _tasks = [for (final t in _tasks) t.id == task.id ? updated : t];
  }

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

Future<void> _pumpCalendar(WidgetTester tester, {int initialTab = 1}) async {
  // 默认 800×600 视口下月历+抓手+面板头部会把任务列表挤到 ~44px，
  // 条目被裁剪导致 tap 落空；用更高视口贴近真机比例。
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sqliteCalendarRepositoryProvider.overrideWithValue(_FakeRepo()),
        sqliteSettingsRepositoryProvider.overrideWithValue(_FakeSettings()),
      ],
      child: MaterialApp(home: CalendarPage(initialTab: initialTab)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('月视图：五页签胶囊在场，月历与任务面板渲染', (tester) async {
    await _pumpCalendar(tester);

    // 胶囊导航在场（五枚页签按钮由 CalendarCapsuleNav 渲染）。
    // 深度层叠转场下相邻面板常驻树中，文本断言一律按组件作用域收窄。
    final nav = find.byType(CalendarCapsuleNav);
    expect(nav, findsOneWidget);
    for (final tab in const ['年', '月', '周', '日', '日程']) {
      expect(
        find.descendant(of: nav, matching: find.text(tab)),
        findsOneWidget,
        reason: '胶囊页签 $tab',
      );
    }

    // 任务面板头部：日期标签与计数。
    final monthPane = find.byType(CalendarMonthPane);
    expect(
      find.descendant(of: monthPane, matching: find.textContaining('已完成')),
      findsOneWidget,
      reason: '月页下半区应显示选中日任务计数',
    );
    // 今天的任务出现在面板。
    expect(
      find.descendant(of: monthPane, matching: find.text('晨会')),
      findsOneWidget,
    );
  });

  testWidgets('切「日程」：按天分组渲染（今天/明天）', (tester) async {
    await _pumpCalendar(tester, initialTab: 4);

    final agenda = find.byType(CalendarAgendaPane);
    expect(agenda, findsOneWidget);
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('明天'), findsOneWidget);
    expect(
      find.descendant(of: agenda, matching: find.text('晨会')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: agenda, matching: find.text('竹林散步')),
      findsOneWidget,
    );
  });

  testWidgets('切「日」：时间轴事件块渲染', (tester) async {
    await _pumpCalendar(tester, initialTab: 3);

    // 周面板与日面板在 tab 3 双双渲染（dRaw=1），日面板在行序中靠后。
    final timeline = find.byType(CalendarTimeline).last;
    expect(
      find.descendant(of: timeline, matching: find.text('晨会')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: timeline, matching: find.text('团队周会')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: timeline, matching: find.text('06:00')),
      findsOneWidget,
    ); // 时间轴起始行
  });

  testWidgets('月视图：点抓手可切换收展（弹簧动画后稳定）', (tester) async {
    await _pumpCalendar(tester, initialTab: 1);

    // 抓手（chevron 图标）在场。
    final handle = find.byIcon(Icons.keyboard_arrow_down);
    expect(handle, findsOneWidget);

    // 点抓手 → 收起：标题切换为周态文案。
    await tester.tap(handle);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      find.textContaining('第'),
      findsOneWidget,
      reason: '收起态标题应为「N月 · 第N周」',
    );

    // 再点 → 展开回月态标题（图标恒为 arrow_down，靠旋转表达方向）。
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('第'), findsNothing);
  });

  testWidgets('点胶囊页签：activeIndex 与标题跟随切换', (tester) async {
    await _pumpCalendar(tester, initialTab: 1);

    await tester.tap(
      find.descendant(
        of: find.byType(CalendarCapsuleNav),
        matching: find.text('周'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<CalendarCapsuleNav>(find.byType(CalendarCapsuleNav))
          .activeIndex,
      2,
      reason: '胶囊高亮的页签真值必须同步到「周」',
    );
  });

  testWidgets('月页纵向拖拽收成单周行：页签仍停在月', (tester) async {
    await _pumpCalendar(tester, initialTab: 1);

    // 月历网格上半区向上拖：收展弹簧落到 0 后只收起中间几行日期。
    final today = DateTime.now();
    await tester.drag(
      find
          .descendant(
            of: find.byType(CalendarMonthGridContent),
            matching: find.text('${today.day}'),
          )
          .first,
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<CalendarCapsuleNav>(find.byType(CalendarCapsuleNav))
          .activeIndex,
      1,
      reason: '月面板收成一行只是月页的固有形态，页签不应跳到「周」',
    );
    final monthPane = tester.widget<CalendarMonthPane>(
      find.byType(CalendarMonthPane),
    );
    expect(
      monthPane.collapse.value,
      closeTo(0, 0.001),
      reason: '拖到上方后月历应稳定停在单周行',
    );
    expect(
      find.textContaining('第'),
      findsOneWidget,
      reason: '收起态标题应为「N月 · 第N周」',
    );
  });

  testWidgets('任务面板短内容上滑：整面板收成单周行（页签不动）', (tester) async {
    await _pumpCalendar(tester, initialTab: 1);

    // 任务不足一屏时列表本身不可滚动，纵向拖拽直接驱动月历收展。
    await tester.drag(
      find.descendant(
        of: find.byType(CalendarMonthPane),
        matching: find.text('晨会'),
      ),
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<CalendarCapsuleNav>(find.byType(CalendarCapsuleNav))
          .activeIndex,
      1,
    );
    expect(
      tester
          .widget<CalendarMonthPane>(find.byType(CalendarMonthPane))
          .collapse
          .value,
      closeTo(0, 0.001),
    );
  });

  testWidgets('日视图任务块：拖下边缘拉长时长并回写仓储', (tester) async {
    final repo = _FakeRepo();
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sqliteCalendarRepositoryProvider.overrideWithValue(repo),
          sqliteSettingsRepositoryProvider.overrideWithValue(_FakeSettings()),
        ],
        child: const MaterialApp(home: CalendarPage(initialTab: 3)),
      ),
    );
    await tester.pumpAndSettle();

    final timeline = find.byType(CalendarTimeline).last;
    final block = find.descendant(of: timeline, matching: find.text('晨会'));
    expect(block, findsOneWidget);

    // 下边缘手柄位于任务块底边；向下拖 52px（= 1 小时）后松手。
    final endHandle = find.descendant(
      of: timeline,
      matching: find.byKey(const ValueKey('timeline-resize-end-1')),
    );
    expect(endHandle, findsOneWidget);
    await tester.dragFrom(
      tester.getRect(endHandle).center,
      const Offset(0, 52),
    );
    await tester.pumpAndSettle();

    final task = (await repo.tasksOnDay(
      DateTime.now(),
    )).firstWhere((t) => t.title == '晨会');
    expect(
      task.end!.difference(task.start).inMinutes,
      greaterThan(60),
      reason: '拖动下边缘后结束时间应被拉长',
    );
  });

  testWidgets('重叠事件并排分栏：同列重叠任务泳道并排不叠画', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final repo = _FakeRepo(
      extra: [
        CalendarTask(
          id: 4,
          title: '头脑风暴',
          // 与「晨会」（9:00-10:00）重叠 → 必须分泳道并排。
          start: today.add(const Duration(minutes: 9 * 60 + 30)),
          end: today.add(const Duration(minutes: 10 * 60 + 30)),
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sqliteCalendarRepositoryProvider.overrideWithValue(repo),
          sqliteSettingsRepositoryProvider.overrideWithValue(_FakeSettings()),
        ],
        child: const MaterialApp(home: CalendarPage(initialTab: 3)),
      ),
    );
    await tester.pumpAndSettle();

    final timeline = find.byType(CalendarTimeline).last;
    final a = tester.getRect(
      find.descendant(of: timeline, matching: find.text('晨会')),
    );
    final b = tester.getRect(
      find.descendant(of: timeline, matching: find.text('头脑风暴')),
    );
    expect(b.left, greaterThan(a.left + 12), reason: '重叠事件应并排分栏，而不是同一位置叠画');
    // 泳道算法本体（块几何派生自它）：同簇等宽数、泳道号互异。
    final lanes = CalendarTimeline.layoutTimelineLanes(
      await repo.tasksOnDay(DateTime.now()),
    );
    expect(lanes, hasLength(3));
    for (final l in lanes) {
      expect(l.lanes, 2, reason: '${l.task.title} 所在簇应有 2 条泳道');
    }
    final byTitle = {for (final l in lanes) l.task.title: l};
    expect(
      byTitle['晨会']!.lane,
      isNot(byTitle['头脑风暴']!.lane),
      reason: '晨会与头脑风暴时间重叠，必须异泳道',
    );
    expect(
      byTitle['晨会']!.lane,
      byTitle['团队周会']!.lane,
      reason: '团队周会 10:00 开始，恰在晨会结束后，可复用泳道 0',
    );
  });

  testWidgets('拖下边缘 10px：吸附到 15 分钟网格（无松手跳变口径）', (tester) async {
    final repo = _FakeRepo();
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sqliteCalendarRepositoryProvider.overrideWithValue(repo),
          sqliteSettingsRepositoryProvider.overrideWithValue(_FakeSettings()),
        ],
        child: const MaterialApp(home: CalendarPage(initialTab: 3)),
      ),
    );
    await tester.pumpAndSettle();

    final timeline = find.byType(CalendarTimeline).last;
    final endHandle = find.descendant(
      of: timeline,
      matching: find.byKey(const ValueKey('timeline-resize-end-1')),
    );
    // 10px ≈ 11.5 分钟 → 吸附 15 分钟；rowHeight 52 → 15 分钟 = 13px。
    await tester.dragFrom(
      tester.getRect(endHandle).center,
      const Offset(0, 10),
    );
    await tester.pumpAndSettle();

    final task = (await repo.tasksOnDay(
      DateTime.now(),
    )).firstWhere((t) => t.title == '晨会');
    expect(
      task.end!.difference(task.start).inMinutes,
      75,
      reason: '9:00-10:00 的任务下缘拖 10px 后应吸附到 10:15',
    );
  });

  testWidgets('30 分钟短事件也有上下拖拽手柄', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final repo = _FakeRepo(
      extra: [
        CalendarTask(
          id: 5,
          title: '小憩',
          start: today.add(const Duration(hours: 13)),
          end: today.add(const Duration(hours: 13, minutes: 30)),
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sqliteCalendarRepositoryProvider.overrideWithValue(repo),
          sqliteSettingsRepositoryProvider.overrideWithValue(_FakeSettings()),
        ],
        child: const MaterialApp(home: CalendarPage(initialTab: 3)),
      ),
    );
    await tester.pumpAndSettle();

    final timeline = find.byType(CalendarTimeline).last;
    expect(
      find.descendant(
        of: timeline,
        matching: find.byKey(const ValueKey('timeline-resize-start-5')),
      ),
      findsOneWidget,
      reason: '短事件（高 26px）也应有上缘手柄',
    );
    expect(
      find.descendant(
        of: timeline,
        matching: find.byKey(const ValueKey('timeline-resize-end-5')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('任务勾选：完成态切换并回写仓储', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final repo = _FakeRepo();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sqliteCalendarRepositoryProvider.overrideWithValue(repo),
          sqliteSettingsRepositoryProvider.overrideWithValue(_FakeSettings()),
        ],
        child: const MaterialApp(home: CalendarPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(CalendarMonthPane),
        matching: find.text('晨会'),
      ),
    );
    await tester.pumpAndSettle();

    final task = (await repo.tasksOnDay(DateTime.now())).first;
    expect(task.completed, true);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });
}
