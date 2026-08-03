import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/recorder/recorder_controller.dart';
import 'package:xiaodouzi_fr/lab/demos/recorder/recorder_list_page.dart';
import 'package:xiaodouzi_fr/lab/demos/recorder/recording_file.dart';

class _FakeRecorderController extends RecorderController {
  _FakeRecorderController(this._files);
  final List<RecordingFile> _files;

  @override
  Future<List<RecordingFile>> listRecordings() async => _files;
}

RecordingFile _file(String name, DateTime modified, {int size = 128000}) =>
    RecordingFile(
      path: '/x/$name',
      name: name,
      sizeBytes: size,
      lastModified: modified,
      duration: const Duration(seconds: 10),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const recordChannel = MethodChannel('com.llfbandit.record/messages');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(recordChannel, (call) async => null);

  group('RecorderListPage 排序/分组 chrome', () {
    testWidgets('切排序(时间·最新 → 时间·最旧)重排列表', (tester) async {
      final newer = 'rec_2026-08-03T10-00-00.aac';
      final older = 'rec_2026-08-03T09-00-00.aac';
      final controller = _FakeRecorderController([
        _file(newer, DateTime(2026, 8, 3, 10)),
        _file(older, DateTime(2026, 8, 3, 9)),
      ]);
      await tester.pumpWidget(
        MaterialApp(home: RecorderListPage(controller: controller)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 默认时间·最新:newer 在上
      expect(tester.getTopLeft(find.text(newer)).dy,
          lessThan(tester.getTopLeft(find.text(older)).dy));

      // 打开排序菜单,选 时间·最旧
      await tester.tap(find.byIcon(Icons.swap_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('时间·最旧').last);
      await tester.pumpAndSettle();

      // older 现在在上
      expect(tester.getTopLeft(find.text(older)).dy,
          lessThan(tester.getTopLeft(find.text(newer)).dy));

      controller.dispose();
    });

    testWidgets('开按日期分组显示 今天/昨天 section 头', (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 12);
      final yesterday = today.subtract(const Duration(days: 1));
      final controller = _FakeRecorderController([
        _file('rec_2026-08-03T10-00-00.aac', today),
        _file('rec_2026-08-03T09-00-00.aac', yesterday),
      ]);
      await tester.pumpWidget(
        MaterialApp(home: RecorderListPage(controller: controller)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 默认不分组:无 section 头
      expect(find.text('今天'), findsNothing);
      expect(find.text('昨天'), findsNothing);

      // 打开按日期分组
      await tester.tap(find.text('按日期'));
      await tester.pumpAndSettle();

      expect(find.text('今天'), findsOneWidget);
      expect(find.text('昨天'), findsOneWidget);
      // 再点关闭
      await tester.tap(find.text('按日期'));
      await tester.pumpAndSettle();
      expect(find.text('今天'), findsNothing);

      controller.dispose();
    });
  });
}
