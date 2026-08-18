// test/lab/demos/calendar/day_cell_event_dot_test.dart
// DayCell 事件彩色小圆点渲染测试。
// 设计：MonthGrid 负责把 Event.colorTag 转成 List<Color> 传进来（含 inMonth 过滤），
// DayCell 只负责渲染。因此这里直接传 eventDotColors 验证渲染，不依赖 GoogleFonts。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/ui/widgets/day_cell.dart';

void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: SizedBox(width: 60, height: 60, child: child)));

  Finder circlesFinder() => find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final d = w.decoration;
        return d is BoxDecoration && d.shape == BoxShape.circle;
      });

  testWidgets('有 eventDotColors → 渲染 4px 彩色小圆点（多色各一个）', (tester) async {
    await tester.pumpWidget(wrap(DayCell(
      date: DateTime(2026, 8, 11),
      inCurrentMonth: false, // 避免 LunarLabel/GoogleFonts，仅测圆点渲染
      isToday: false,
      events: const [],
      eventDotColors: const [Color(0xFFC8553D), Color(0xFFE9B44C)],
    )));
    // 2 个不同颜色圆点 + 可能的外圈（isToday=false 无外圈）→ 正好 2 个 circle
    expect(circlesFinder(), findsNWidgets(2));
  });

  testWidgets('无 eventDotColors → 不渲染圆点', (tester) async {
    await tester.pumpWidget(wrap(DayCell(
      date: DateTime(2026, 8, 11),
      inCurrentMonth: false,
      isToday: false,
      events: const [],
      eventDotColors: const [],
    )));
    expect(circlesFinder(), findsNothing);
  });

  testWidgets('事件自带默认色（不传 eventDotColors）→ 兼容旧调用不渲染圆点', (tester) async {
    // 旧调用（如 day_cell_default_font_test）不传 eventDotColors，走默认 const []
    await tester.pumpWidget(wrap(DayCell(
      date: DateTime(2026, 8, 11),
      inCurrentMonth: false,
      isToday: false,
      events: const [],
    )));
    expect(circlesFinder(), findsNothing);
  });
}
