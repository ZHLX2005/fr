# Calendar View Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a conditional "今天" pill button to the month view header, and bottom color dots on day cells that have events (any type).

**Architecture:** Small, purely visual enhancements to existing components. Provider gets one new getter (`isOnCurrentMonth`) for the visibility check; MonthView reads it to gate the pill; MonthGrid extracts distinct `Event.colorTag`s per cell and passes them to DayCell; DayCell renders a 4px row of dots below the date number.

**Tech Stack:** Flutter / Dart, `provider`, `PaperPalette`, `Event.colorTag` (8 hex colors, already on the model).

**Spec:** `.claude/repo/_self/calendar-view-polish-intent.md`

**Tests reference:** `test/lab/demos/calendar/day_cell_default_font_test.dart` (existing pattern: pump `MaterialApp → Scaffold → DayCell`, then `find.text`/assertion)

## Global Constraints

- Project is `xiaodouzi/fr` (Flutter, `package:xiaodouzi_fr/...`)
- Visual style: paper-feel palette, **no fills on buttons**, 1px outlines only
- Color: `Event.colorTag.hex` is a 6-char hex like `'#C8553D'` — parse with `Color(0xFF${hex.substring(1)})`
- `PaperPalette.today` = `0xFFC8553D` (朱砂红) for the pill text/outline
- The `LunarLabel` widget is already GoogleFonts-backed; tests must pass `inCurrentMonth: false` if they don't want it rendered (existing pattern in `day_cell_default_font_test.dart`)
- Year wrapping: `setView` in provider already handles `m <= 0` / `m > 12`, so jumping "back to current month" across year boundary is automatic
- Do **not** add new dependencies; do **not** introduce a new color palette

---

### Task 1: Add `isOnCurrentMonth` getter to `LabCalendarProvider`

**Files:**
- Modify: `lib/lab/demos/calendar/data/lab_calendar_provider.dart:27-29` (add getter after `viewMonth` getter)
- Test: `test/lab/demos/calendar/calendar_provider_ready_test.dart` (extend existing file with one new test case)

**Interfaces:**
- Produces: `bool isOnCurrentMonth` — true when `_viewYear == today.year && _viewMonth == today.month`

- [ ] **Step 1: Write the failing test**

Append to `test/lab/demos/calendar/calendar_provider_ready_test.dart` (after existing `main` body, or in a new `group` if preferred):

```dart
import 'package:xiaodouzi_fr/lab/demos/calendar/data/lab_calendar_provider.dart';

test('isOnCurrentMonth 与 viewYear/viewMonth 同步', () async {
  final p = LabCalendarProvider();
  // 等 ready（Hive init + loadAll）
  while (!p.ready) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  final n = DateTime.now();
  expect(p.isOnCurrentMonth, isTrue); // 初始就是当月
  await p.setView(2000, 1);
  expect(p.isOnCurrentMonth, isFalse);
  await p.jumpToday();
  expect(p.isOnCurrentMonth, isTrue);
});
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `flutter test test/lab/demos/calendar/calendar_provider_ready_test.dart`
Expected: FAIL with `NoSuchMethodError` / undefined getter on `isOnCurrentMonth`.

- [ ] **Step 3: Add the getter**

In `lib/lab/demos/calendar/data/lab_calendar_provider.dart`, right after the `int get viewMonth => _viewMonth;` line (around L29), add:

```dart
/// 是否正显示当前月（用于头部"今天"按钮的可见性判定）
bool get isOnCurrentMonth {
  final n = DateTime.now();
  return _viewYear == n.year && _viewMonth == n.month;
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `flutter test test/lab/demos/calendar/calendar_provider_ready_test.dart`
Expected: PASS (1 test, may have more in file).

- [ ] **Step 5: Commit**

```bash
git add lib/lab/demos/calendar/data/lab_calendar_provider.dart test/lab/demos/calendar/calendar_provider_ready_test.dart
git commit -m "feat(calendar): add isOnCurrentMonth getter to LabCalendarProvider"
```

---

### Task 2: Conditional "今天" pill button in `MonthView`

**Files:**
- Modify: `lib/lab/demos/calendar/ui/month_view.dart:33-48` (replace `Expanded(Center(Text(...)))` with row that conditionally inserts a pill)
- Test: `test/lab/demos/calendar/month_view_today_pill_test.dart` (new file)

**Interfaces:**
- Consumes: `LabCalendarProvider.isOnCurrentMonth` (from Task 1), `LabCalendarProvider.jumpToday()` (existing)
- Produces: a pill button rendered only when `!isOnCurrentMonth`; tapping calls `p.jumpToday()`

- [ ] **Step 1: Write the failing test**

Create `test/lab/demos/calendar/month_view_today_pill_test.dart`:

```dart
// test/lab/demos/calendar/month_view_today_pill_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/data/lab_calendar_provider.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/ui/month_view.dart';

Widget _wrap(LabCalendarProvider p, Widget child) {
  return MaterialApp(
    home: ChangeNotifierProvider<LabCalendarProvider>.value(
      value: p,
      child: Scaffold(body: SizedBox(width: 400, height: 700, child: child)),
    ),
  );
}

void main() {
  testWidgets('当前月时无"今天"药丸', (tester) async {
    final p = LabCalendarProvider();
    while (!p.ready) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await tester.pumpWidget(_wrap(p, MonthView(onDayTap: (_) {}, onDayLongPress: (_) {})));
    await tester.pump();
    expect(find.text('今天'), findsNothing);
  });

  testWidgets('非当前月显示"今天"药丸；点击后跳回并消失', (tester) async {
    final p = LabCalendarProvider();
    while (!p.ready) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await p.setView(2000, 1); // 远离当月
    await tester.pumpWidget(_wrap(p, MonthView(onDayTap: (_) {}, onDayLongPress: (_) {})));
    await tester.pump();
    expect(find.text('今天'), findsOneWidget);

    await tester.tap(find.text('今天'));
    await tester.pumpAndSettle();
    expect(p.isOnCurrentMonth, isTrue);
    expect(find.text('今天'), findsNothing);
  });
}
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `flutter test test/lab/demos/calendar/month_view_today_pill_test.dart`
Expected: FAIL (no "今天" text rendered at all in either case).

- [ ] **Step 3: Modify MonthView header to render the pill conditionally**

In `lib/lab/demos/calendar/ui/month_view.dart`, replace the `Expanded(child: Center(child: GestureDetector(...)))` block (around L33-48) with a row that includes a conditional pill. The new structure:

```dart
Expanded(
  child: Center(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: p.jumpToday,
          child: Text(
            '${p.viewYear}年${p.viewMonth}月',
            style: const TextStyle(
              color: PaperPalette.ink,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ),
        if (!p.isOnCurrentMonth) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: p.jumpToday,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                border: Border.all(color: PaperPalette.today, width: 1),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                '今天',
                style: TextStyle(
                  color: PaperPalette.today,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  ),
),
```

Notes:
- `mainAxisSize: MainAxisSize.min` keeps the title+pill cluster centered.
- The original `GestureDetector` on the title is preserved (still calls `jumpToday`).
- Pill is no-fill, 1px 朱砂红描边, 圆角 999（药丸）。

- [ ] **Step 4: Run the test and confirm it passes**

Run: `flutter test test/lab/demos/calendar/month_view_today_pill_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Run the full calendar test suite to confirm no regression**

Run: `flutter test test/lab/demos/calendar/`
Expected: all PASS (existing tests still green).

- [ ] **Step 6: Commit**

```bash
git add lib/lab/demos/calendar/ui/month_view.dart test/lab/demos/calendar/month_view_today_pill_test.dart
git commit -m "feat(calendar): show '今天' pill in MonthView when not on current month"
```

---

### Task 3: Distinct color dots in `DayCell` (Task 43)

**Files:**
- Modify: `lib/lab/demos/calendar/ui/widgets/day_cell.dart:14-32` (add `eventDotColors: List<Color>` param), `lib/lab/demos/calendar/ui/widgets/day_cell.dart:97-116` (render dots below avatar row, only if `inCurrentMonth && events without people`)
- Modify: `lib/lab/demos/calendar/ui/widgets/month_grid.dart:60-73` (compute dot colors from events, pass to DayCell)
- Test: `test/lab/demos/calendar/day_cell_event_dot_test.dart` (new file)

**Interfaces:**
- Consumes: `Event.colorTag.hex` (8-color enum, e.g. `'#C8553D'`) → `Color(0xFF${hex.substring(1)})`
- Produces: DayCell renders a row of 4px colored dots below the avatar row, only when `inCurrentMonth && eventDotColors.isNotEmpty`. Birthday's existing top-right yellow dot stays unchanged.

Helper for hex → Color, defined inline in `month_grid.dart` (no new file needed):

```dart
Color _hexToColor(String hex) {
  // hex like '#C8553D' → 0xFFC8553D
  return Color(int.parse('FF${hex.substring(1)}', radix: 16));
}
```

- [ ] **Step 1: Write the failing test**

Create `test/lab/demos/calendar/day_cell_event_dot_test.dart`:

```dart
// test/lab/demos/calendar/day_cell_event_dot_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/event.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/recurrence.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/ui/widgets/day_cell.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: SizedBox(width: 80, height: 80, child: child)),
      );

  Event _mkEvent(ColorTag tag) => Event(
        id: 'e1',
        type: EventType.custom,
        title: 't',
        system: CalendarSystem.solar,
        year: 2026,
        month: 8,
        day: 11,
        recurrence: Recurrence.none,
        colorTag: tag,
        createdAt: DateTime(2026, 1, 1),
      );

  testWidgets('有事件(无 personId) → 渲染底部彩色小圆点', (tester) async {
    await tester.pumpWidget(wrap(DayCell(
      date: DateTime(2026, 8, 11),
      inCurrentMonth: true,
      isToday: false,
      events: [_mkEvent(ColorTag.red)],
      eventDotColors: const [Color(0xFFC8553D)],
    )));
    // 找到至少 1 个 BoxDecoration 圆形（4x4 的 Container）
    // 用 Container 数来兜底：原 cell 已有 Container（外圈 Stack），新增的内层 dot Container 应存在
    // 更稳的判定：找 text 11 下方 / 用 tester 找带 border 的 Container
    // 这里用 paintBounds 的方式无法直接取，圆点本身没有文字。
    // 替代断言：cell 包含至少 1 个 BoxShape.circle 的 Decoration
    final circles = find.byWidgetPredicate((w) {
      if (w is! Container) return false;
      final d = w.decoration;
      return d is BoxDecoration && d.shape == BoxShape.circle;
    });
    expect(circles, findsWidgets); // 至少能找到 circle 装饰
  });

  testWidgets('无事件 → 不渲染事件圆点', (tester) async {
    await tester.pumpWidget(wrap(DayCell(
      date: DateTime(2026, 8, 11),
      inCurrentMonth: true,
      isToday: false,
      events: const [],
      eventDotColors: const [],
    )));
    // isToday=false, 无事件, 无 people → 不应有任何圆点
    final circles = find.byWidgetPredicate((w) {
      if (w is! Container) return false;
      final d = w.decoration;
      return d is BoxDecoration && d.shape == BoxShape.circle;
    });
    expect(circles, findsNothing);
  });

  testWidgets('inCurrentMonth=false → 即便有事件也不渲染圆点', (tester) async {
    await tester.pumpWidget(wrap(DayCell(
      date: DateTime(2026, 8, 11),
      inCurrentMonth: false,
      isToday: false,
      events: [_mkEvent(ColorTag.red)],
      eventDotColors: const [Color(0xFFC8553D)],
    )));
    final circles = find.byWidgetPredicate((w) {
      if (w is! Container) return false;
      final d = w.decoration;
      return d is BoxDecoration && d.shape == BoxShape.circle;
    });
    expect(circles, findsNothing);
  });
}
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `flutter test test/lab/demos/calendar/day_cell_event_dot_test.dart`
Expected: FAIL — `DayCell` does not have an `eventDotColors` parameter yet → analyzer error or constructor mismatch.

- [ ] **Step 3: Add `eventDotColors` param + render dots in DayCell**

In `lib/lab/demos/calendar/ui/widgets/day_cell.dart`:

1. Add to constructor params (after `people`):
```dart
final List<Color> eventDotColors;
// ...
this.eventDotColors = const [],
```

2. In the `Stack` children, after the existing avatar `Positioned` (around L116), add a new `Positioned` for the dot row:
```dart
// 事件彩色小圆点（多色横排，贴底部中线）
if (eventDotColors.isNotEmpty)
  Positioned(
    bottom: 0,
    left: 0,
    right: 0,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final c in eventDotColors) ...[
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 2),
        ],
      ],
    ),
  ),
```

3. Conditional already covers `inCurrentMonth` upstream in `MonthGrid` (see Step 4) — DayCell itself just trusts the prop.

- [ ] **Step 4: Wire `MonthGrid` to compute and pass dot colors**

In `lib/lab/demos/calendar/ui/widgets/month_grid.dart`, replace lines 60-73 (the DayCell constructor call) with:

```dart
Color _hexToColor(String hex) =>
    Color(int.parse('FF${hex.substring(1)}', radix: 16));

// ... in itemBuilder, replace events/evPeople + DayCell construction:
final events = cal.eventsOnDate(date);
final evPeople = <Person>[
  for (final e in events)
    if (e.personId != null)
      if (people.byId(e.personId!) != null) people.byId(e.personId!)!,
];
// 取所有事件的 colorTag 去重（保持插入顺序）
final seen = <String>{};
final dotColors = <Color>[];
for (final e in events) {
  if (seen.add(e.colorTag.name)) {
    dotColors.add(_hexToColor(e.colorTag.hex));
  }
}
return DayCell(
  date: date,
  inCurrentMonth: inMonth,
  isToday: isToday,
  events: events,
  people: evPeople,
  eventDotColors: inMonth ? dotColors : const [],
  onTap: inMonth ? () => onDayTap(date) : null,
  onLongPress: inMonth ? () => onDayLongPress(date) : null,
);
```

- [ ] **Step 5: Run the test and confirm it passes**

Run: `flutter test test/lab/demos/calendar/day_cell_event_dot_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Run the full calendar test suite to confirm no regression**

Run: `flutter test test/lab/demos/calendar/`
Expected: all PASS. Pay special attention to `day_cell_default_font_test.dart` — it doesn't pass `eventDotColors`, so the new default `const []` must keep it working.

- [ ] **Step 7: Commit**

```bash
git add lib/lab/demos/calendar/ui/widgets/day_cell.dart lib/lab/demos/calendar/ui/widgets/month_grid.dart test/lab/demos/calendar/day_cell_event_dot_test.dart
git commit -m "feat(calendar): render bottom color dots on day cells with events"
```

---

### Task 4: Final verify, push, and backfill kvcli todo

**Files:** (no source changes; admin only)

- [ ] **Step 1: Run full calendar test suite one more time**

Run: `flutter test test/lab/demos/calendar/`
Expected: all PASS.

- [ ] **Step 2: Run analyze on the changed files only**

Run: `flutter analyze lib/lab/demos/calendar/ test/lab/demos/calendar/`
Expected: no new issues (existing analyzer hints, if any, may stay).

- [ ] **Step 3: Push the commits**

```bash
git push
```

- [ ] **Step 4: Backfill kvcli todo for IDs 27 and 43**

```bash
kvcli todo done 27 --result "feat(calendar): add isOnCurrentMonth getter + '今天' pill in MonthView (条件显示); 2 widget tests pass; commit + push"
kvcli todo done 43 --result "feat(calendar): DayCell 底部 4px 彩色小圆点, 按 Event.colorTag 去重横排; 3 widget tests pass; commit + push"
```

Expected: each command reports success and moves the task from `open` to `done`.

- [ ] **Step 5: Verify open queue is empty for fr topic**

```bash
kvcli todo --open --topic fr
```

Expected: empty / "暂无待办" / `[ ] 待办 (0)`.
