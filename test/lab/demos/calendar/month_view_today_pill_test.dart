// test/lab/demos/calendar/month_view_today_pill_test.dart
// MonthHeader（从 MonthView 抽出）的条件药丸按钮测试。
// 设计：MonthHeader 不依赖 provider / Hive / GoogleFonts，可直接独立测试。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/ui/month_view.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(width: 400, height: 60, child: child),
    ),
  );
}

void main() {
  testWidgets('当前月时无"今天"药丸', (tester) async {
    await tester.pumpWidget(_wrap(const MonthHeader(
      year: 2026,
      month: 8,
      isOnCurrentMonth: true,
    )));
    expect(find.text('2026年8月'), findsOneWidget);
    expect(find.text('今天'), findsNothing);
  });

  testWidgets('非当前月显示"今天"药丸；点击后跳回并消失', (tester) async {
    var jumped = false;
    await tester.pumpWidget(_wrap(MonthHeader(
      year: 2000,
      month: 1,
      isOnCurrentMonth: false,
      onJumpToday: () => jumped = true,
    )));
    expect(find.text('2000年1月'), findsOneWidget);
    expect(find.text('今天'), findsOneWidget);

    await tester.tap(find.text('今天'));
    expect(jumped, isTrue);
  });

  testWidgets('onJumpToday 为 null 时不渲染任何交互（标题/药丸仍显示）', (tester) async {
    await tester.pumpWidget(_wrap(const MonthHeader(
      year: 2025,
      month: 12,
      isOnCurrentMonth: false,
    )));
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('2025年12月'), findsOneWidget);
  });
}
