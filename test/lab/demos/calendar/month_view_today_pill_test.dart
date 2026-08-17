// test/lab/demos/calendar/month_view_today_pill_test.dart
// MonthView 的条件药丸按钮测试。
// 注意：完整渲染 MonthView 会触发 GoogleFonts 网络请求（LunarLabel），
// 测试环境中无法可靠完成。因此 widget 级渲染测试只验证"非当前月"场景，
// "当前月"场景由 provider 测试（calendar_provider_ready_test.dart）覆盖。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/data/lab_calendar_provider.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/data/lab_people_provider.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/ui/month_view.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('month_view_pill_test');
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('home_widget'),
      (call) async => null,
    );
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('非当前月显示"今天"药丸；点击后跳回并消失', (tester) async {
    final p = LabCalendarProvider();
    final pe = LabPeopleProvider();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await p.setView(2000, 1); // 远离当月

    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<LabCalendarProvider>.value(value: p),
            ChangeNotifierProvider<LabPeopleProvider>.value(value: pe),
          ],
          child: Scaffold(
            body: SizedBox(
              width: 400,
              height: 700,
              child: MonthView(
                onDayTap: (_) {},
                onDayLongPress: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    // 多次 pump 让 GoogleFonts 异步加载超时 fallback
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('今天'), findsOneWidget);

    await tester.tap(find.text('今天'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(p.isOnCurrentMonth, isTrue);
    expect(find.text('今天'), findsNothing);
  });
}