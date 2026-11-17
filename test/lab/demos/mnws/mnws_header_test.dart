// 回归 fr #9「这个页面存在两个头部」。
//
// 外壳 `DemoDetailPage` 会给一条 48dp 的居中标题（demo.title），mn-ws 首页自己
// 也带 AppBar（标题 + 请求台/设置/刷新）。两段叠着就是两条头部 —— 靠
// `preferFullScreen` 让外壳不加 AppBar，这里把它钉住。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/mnws/mnws_demo.dart';
import 'package:xiaodouzi_fr/screens/profile/lab/demo_detail_page.dart';

void main() {
  testWidgets('mn-ws 首页只长一条头部，标题就是底栏那颗 tab 的名字', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: DemoDetailPage(demo: MnWsDemo()),
      ),
    ));
    // 首页 initState 会探一次服务（测试里没有网），只等一帧编排，不等它 settle
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AppBar), findsOneWidget, reason: '外壳 + 内页各一条就是两条头部');
    expect(find.text('mn-ws 双向桥'), findsOneWidget);
    expect(find.text('mn-ws 桥接'), findsNothing, reason: '同一样东西别再叫两个名字');
  });
}
