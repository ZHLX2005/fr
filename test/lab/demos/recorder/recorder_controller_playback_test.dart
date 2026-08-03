import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/recorder/recorder_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 同 recorder_controller_amplitude_test:record 插件 method channel 装 null mock,
  // 让 AudioRecorder() 构造/释放静默通过。
  const recordChannel = MethodChannel('com.llfbandit.record/messages');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(recordChannel, (call) async => null);

  group('RecorderController 播放可观察量', () {
    test('初始:未播放、位置 0、时长 null', () {
      final c = RecorderController();
      expect(c.isPlaying, isFalse);
      expect(c.playbackPosition.value, Duration.zero);
      expect(c.playbackDuration.value, isNull);
      c.dispose();
    });

    test('播放 notifier dispose 后仍可安全读取', () {
      final c = RecorderController();
      c.dispose();
      expect(() => c.playbackPosition.value, returnsNormally);
      expect(() => c.playbackDuration.value, returnsNormally);
    });

    test('isPlaying 跟随 _player(构造后 false)', () {
      final c = RecorderController();
      expect(c.isPlaying, isFalse);
      c.dispose();
    });
  });
}
