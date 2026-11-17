// fr #11：语音合成那一支整页删掉，「API 测试」直接就是 APK 下载页。
//
// 这里钉两件事：页面里不再有 TabBar（两个 Tab 只留一个时它就是白多一层）；
// 以及内容确实是 APK 那一屏（检查更新 / 内部下载 / 下载地址），不是被删空的壳。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/lab/demos/api_test_demo.dart';
import 'package:xiaodouzi_fr/screens/profile/lab/demo_detail_page.dart';

void main() {
  testWidgets('API 测试 → 直接是 APK 下载页：没有 Tab、语音合成不再出现', (tester) async {
    // 下载管理器要读 SharedPreferences（已下载路径 / 自动下载开关）
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: DemoDetailPage(demo: ApiTestDemo()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(TabBar), findsNothing, reason: '只剩一屏内容，Tab 栏就是多出来的一层');
    expect(find.text('语音合成'), findsNothing);
    expect(find.text('APK 下载'), findsOneWidget);

    // 内容还是原来那一屏（不是删空的壳）
    expect(find.text('FR 最新版 APK'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
    expect(find.text('内部下载'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
