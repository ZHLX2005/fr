// test/lab/demos/calendar/calendar_provider_ready_test.dart
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/data/lab_calendar_provider.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/data/lab_people_provider.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    // CalendarRepository.instance 是进程级单例，Hive 目录须跨用例共享；
    // 否则 test 1 删目录后 test 2 复用单例指向已删路径 → PathNotFoundException。
    tempDir = Directory.systemTemp.createTempSync('calendar_ready_test');
    // HiveStore.init → Hive.initFlutter 依赖 path_provider，桩成临时目录
    // （参照 test/core/storage/export/storage_exporter_test.dart 模式）。
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    // home_widget 桌面小组件同步（_loadAll 里 _syncToWidget 会调 saveWidgetData）：
    // 桩成功返回，避免 MissingPluginException 中断 _init 的 ready 置位。
    messenger.setMockMethodCallHandler(
      const MethodChannel('home_widget'),
      (call) async => null,
    );
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('构造后同帧 ready==false（数据未加载完成）', () {
    final cal = LabCalendarProvider();
    final people = LabPeopleProvider();
    expect(cal.ready, isFalse);
    expect(people.ready, isFalse);
  });

  test('await CalendarRepository.init 后 ready 变为 true', () async {
    final cal = LabCalendarProvider();
    final people = LabPeopleProvider();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(cal.ready, isTrue);
    expect(people.ready, isTrue);
  });

  test('isOnCurrentMonth 与 viewYear/viewMonth 同步', () async {
    final cal = LabCalendarProvider();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(cal.ready, isTrue);
    expect(cal.isOnCurrentMonth, isTrue); // 初始就是当月
    await cal.setView(2000, 1);
    expect(cal.isOnCurrentMonth, isFalse);
    await cal.jumpToday();
    expect(cal.isOnCurrentMonth, isTrue);
  });
}
