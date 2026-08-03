import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/recorder/recorder_controller.dart';
import 'package:xiaodouzi_fr/lab/demos/recorder/recorder_list_page.dart';
import 'package:xiaodouzi_fr/lab/demos/recorder/recording_file.dart';

/// 用固定文件列表替代 listRecordings,避开 path_provider 插件。
class _FakeRecorderController extends RecorderController {
  _FakeRecorderController(this._files);
  final List<RecordingFile> _files;

  @override
  Future<List<RecordingFile>> listRecordings() async => _files;
}

RecordingFile _file(String name, DateTime modified) => RecordingFile(
      path: '/x/$name',
      name: name,
      sizeBytes: 128000,
      lastModified: modified,
      duration: const Duration(seconds: 10),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // record 插件 method channel mock(与其它 controller 测试一致)。
  const recordChannel = MethodChannel('com.llfbandit.record/messages');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(recordChannel, (call) async => null);

  group('RecorderListPage 可展开 tile', () {
    testWidgets('点卡片展开时间轴;再点收起', (tester) async {
      final controller = _FakeRecorderController([
        _file('rec_2026-08-03T10-00-00.aac', DateTime(2026, 8, 3, 10)),
      ]);
      await tester.pumpWidget(
        MaterialApp(home: RecorderListPage(controller: controller)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 收起态:无 Slider
      expect(find.byType(Slider), findsNothing);

      // 展开 → 时间轴出现(Slider + 当前时间 + 总时长估算回落)
      await tester.tap(find.text('rec_2026-08-03T10-00-00.aac'));
      await tester.pump();
      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('00:00'), findsOneWidget);
      expect(find.text('00:10'), findsOneWidget);

      // 再点收起 → 时间轴消失
      await tester.tap(find.text('rec_2026-08-03T10-00-00.aac'));
      await tester.pump();
      expect(find.byType(Slider), findsNothing);

      controller.dispose();
    });

    testWidgets('单条展开:展开 B 自动收起 A', (tester) async {
      final controller = _FakeRecorderController([
        _file('rec_2026-08-03T10-00-00.aac', DateTime(2026, 8, 3, 10)),
        _file('rec_2026-08-03T11-00-00.aac', DateTime(2026, 8, 3, 11)),
      ]);
      await tester.pumpWidget(
        MaterialApp(home: RecorderListPage(controller: controller)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 展开 A
      await tester.tap(find.text('rec_2026-08-03T10-00-00.aac'));
      await tester.pump();
      expect(find.byType(Slider), findsOneWidget);

      // 展开 B → A 自动收起,仍只有一个 Slider
      await tester.tap(find.text('rec_2026-08-03T11-00-00.aac'));
      await tester.pump();
      expect(find.byType(Slider), findsOneWidget);

      controller.dispose();
    });
  });
}
