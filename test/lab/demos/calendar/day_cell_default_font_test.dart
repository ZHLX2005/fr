// test/lab/demos/calendar/day_cell_default_font_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/ui/widgets/day_cell.dart';

void main() {
  testWidgets('日数字使用默认字体（无特殊衬线），与全 app 一致', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DayCell(
            date: DateTime(2026, 8, 11),
            // false 跳过农历小字/头像，只渲染日期数字，避免 AppText.caption
            // 的 GoogleFonts 在测试环境异步加载字体。
            inCurrentMonth: false,
            isToday: false,
            events: const [],
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text('11'));
    // 未套 fontFamily/fontFamilyFallback → 走 app 默认字体，而非衬线特殊字体。
    expect(text.style?.fontFamily, isNull);
    expect(text.style?.fontFamilyFallback, isNull);
  });
}
