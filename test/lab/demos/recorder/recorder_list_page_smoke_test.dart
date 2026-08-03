import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/recorder/const_recorder.dart';
import 'package:xiaodouzi_fr/lab/demos/recorder/recorder_controller.dart';
import 'package:xiaodouzi_fr/lab/demos/recorder/recorder_list_page.dart';

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

  // path_provider 的 `getApplicationDocumentsDirectory` 在 widget test 里
  // 无 mock 时不返回(_future 挂起),会让 listRecordings 永远不完成、
  // 页面停在 loading。装一个返回 null 的 mock,触发 path_provider 内部
  // 抛 MissingPlatformDirectoryException,被 listRecordings 的 try/catch
  // 吞掉后返回 [] —— 这正是产品代码在真实环境异常时的回退路径。
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pathProviderChannel, (call) async => null);

  testWidgets('RecorderListPage 空态渲染', (tester) async {
    final controller = RecorderController();
    await tester.pumpWidget(
      MaterialApp(home: RecorderListPage(controller: controller)),
    );
    // listRecordings() 内部 await getApplicationDocumentsDirectory() —— 在
    // flutter_test 上 path_provider mock 返回 null → 抛
    // MissingPlatformDirectoryException,被 listRecordings 的 try/catch 吞掉
    // 后返回 []。多 pump 几帧让这条异步链走完、setState 生效,空态渲染出来
    // (不能用 pumpAndSettle:loading 态的 CircularProgressIndicator 是连续
    // 动画,永不 settle)。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // 注意:依赖沙盒 recordings/ 目录为空。CI 首跑通常为空;
    // 开发者本地若有历史录音,此断言会失败 —— 属预期,可临时跳过。
    expect(find.text(RecorderUiText.emptyList), findsOneWidget);
    controller.dispose();
  });
}
