// AppNotification 布局回归测试 —— 复现「底部溢出黄线」。
//
// 背景：用户报告通知弹窗底部有 RenderFlex overflowed 黄黑条。
// 静态推演 Positioned(top,left,right 无 bottom) 给的是无界约束，
// 理论上不该溢出；这里用各种极端场景实测验证，找出真正触发条件。
//
// widget 测试里 RenderFlex overflow 会以 FlutterError 抛出并直接判测试失败，
// 所以任何一条用例失败 = 复现了溢出，失败信息里带完整 widget 链。

import 'package:xiaodouzi_fr/core/ui/shell/app_notification.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void _show(BuildContext context, String message) =>
    AppNotification.show(context, message, type: AppNotificationType.error);

Future<void> _pumpAndShow(WidgetTester tester, String message) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => _show(context, message),
              child: const Text('GO'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('GO'));
  // 滑入动画 280ms + 回弹过冲，pump 到动画结束让布局完全稳定
  await tester.pump(const Duration(milliseconds: 400));
  // 通知自带自动关闭 Timer（2600ms）+ 退场动画（220ms）——必须全部冲掉，
  // 否则测试结束时挂着的 Timer 会被框架判失败（而非真实溢出）
  await tester.pump(const Duration(milliseconds: 3200));
}

/// rt_page 断连场景：detail 可能是超长异常文本
const _longDetail =
    '连接断开（WebSocketChannelException: SocketException: Connection reset '
    'by peer (OS Error: Software caused connection abort, errno = 103), '
    'address = 1.94.101.189, port = 8790）自动重连已放弃，请检查网络后手动重连';

void main() {
  group('AppNotification 溢出回归', () {
    testWidgets('常规手机尺寸 + 超长断连消息', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await _pumpAndShow(tester, _longDetail);
      expect(tester.takeException(), isNull);
    });

    testWidgets('小屏 320x480 + 超长消息', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _pumpAndShow(tester, _longDetail);
      expect(tester.takeException(), isNull);
    });

    testWidgets('无空格超长 token（不可断行）', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await _pumpAndShow(tester, 'a' * 500);
      expect(tester.takeException(), isNull);
    });

    testWidgets('大字号 textScale 2.0 + 超长消息', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      addTearDown(tester.view.reset);
      await _pumpAndShow(tester, _longDetail);
      expect(tester.takeException(), isNull);
    });

    testWidgets('横屏 800x360 + 超长消息', (tester) async {
      tester.view.physicalSize = const Size(800, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _pumpAndShow(tester, _longDetail);
      expect(tester.takeException(), isNull);
    });

    testWidgets('带换行符的消息', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await _pumpAndShow(tester, '第一行\n第二行\n第三行\n第四行\n第五行\n第六行');
      expect(tester.takeException(), isNull);
    });
  });
}
