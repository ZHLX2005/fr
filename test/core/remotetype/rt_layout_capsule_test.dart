// 布局胶囊 widget 测试：
//   · 每种布局左上角都有同一颗胶囊（状态点 + 当前布局名 + chevron）；
//   · 点开即回调（打开布局面板：第一层是布局列表，最下面是设置入口）；
//   · 胶囊本身不再挂菜单——旧的「模块编排 / 返回写字」旁门都已撤掉。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/remotetype/ui/rt_layout_capsule.dart';

void main() {
  testWidgets('胶囊显示当前布局名，点开回调', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: RtLayoutCapsule(
              connected: true,
              layoutName: '写字',
              onOpen: () => opened++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('写字'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more), findsOneWidget);

    await tester.tap(find.byType(RtLayoutCapsule));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('胶囊在左上角（横竖屏各一份，同一控件）', (tester) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: RtLayoutCapsule(
              connected: false,
              layoutName: '触控屏布局',
              onOpen: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final capsule = tester.getRect(find.byType(RtLayoutCapsule));
    expect(capsule.left, lessThan(40));
    expect(capsule.top, lessThan(40));
  });
}
