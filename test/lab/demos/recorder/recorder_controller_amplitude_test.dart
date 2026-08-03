import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/recorder/recorder_controller.dart';

void main() {
  // RecorderController 构造时实例化 AudioRecorder / AudioPlayer,
  // 二者经 platform channel 通信,需要 binding 已初始化。
  TestWidgetsFlutterBinding.ensureInitialized();

  // AudioRecorder() 构造时异步触发 record 插件 method channel 的 `create`,
  // dispose() 触发 `dispose`。两者在无 mock 的 flutter_test 里会以
  // MissingPluginException 在 test body 结束后才冒出,被判定为"未完成的异步工作"。
  // 这里给 `com.llfbandit.record/messages` 装一个返回 null 的 mock handler,
  // 让构造/dispose 静默通过 —— 不影响本测试要验证的"通道存在 + 初始值 + dispose 安全"。
  const recordChannel = MethodChannel('com.llfbandit.record/messages');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(recordChannel, (call) async => null);

  group('RecorderController dbListenable', () {
    test('初始 dBFS 为 -60(空闲态)', () {
      final c = RecorderController();
      expect(c.dbListenable.value, -60.0);
      c.dispose();
    });

    test('dispose 后 dbListenable 仍可安全读取不抛', () {
      final c = RecorderController();
      c.dispose();
      expect(() => c.dbListenable.value, returnsNormally);
    });

    test('amplitudeDbListenable 是同一个 ValueNotifier', () {
      // 暴露给测试:确认两个 getter 指向同一源
      final c = RecorderController();
      expect(identical(c.dbListenable, c.amplitudeDbListenable), isTrue);
      c.dispose();
    });
  });
}
