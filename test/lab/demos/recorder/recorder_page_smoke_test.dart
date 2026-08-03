import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/recorder/recorder_controller.dart';
import 'package:xiaodouzi_fr/lab/demos/recorder/recorder_page.dart';

void main() {
  // RecorderController 构造时实例化 AudioRecorder / AudioPlayer,
  // 二者经 platform channel 通信,需要 binding 已初始化。
  // 复用 recorder_controller_amplitude_test 的同款 preamble:
  // AudioRecorder() 构造/dispose 走 `com.llfbandit.record/messages`,
  // 无 mock 时会以 MissingPluginException 冒出,被判定为未完成异步工作。
  TestWidgetsFlutterBinding.ensureInitialized();
  const recordChannel = MethodChannel('com.llfbandit.record/messages');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(recordChannel, (call) async => null);

  testWidgets('RecorderPageScaffold idle 态能渲染,无异常', (tester) async {
    final controller = RecorderController();
    await tester.pumpWidget(
      MaterialApp(
        home: RecorderPageScaffold(
          controller: controller,
          onStart: controller.start,
          onPause: controller.pause,
          onResume: controller.resume,
          onStop: controller.stop,
          onSave: () {},
          onDiscard: () {},
        ),
      ),
    );
    expect(find.text('录音机'), findsOneWidget);
    expect(find.text('就绪'), findsOneWidget);
    // hero 录音键存在(fiber_manual_record icon)
    expect(find.byIcon(Icons.fiber_manual_record), findsOneWidget);
    controller.dispose();
  });
}
