import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/core/storage/export/storage_exporter.dart';
import 'package:xiaodouzi_fr/core/storage/export/storage_importer.dart';
import 'package:xiaodouzi_fr/core/storage/storage_registry.dart';
import 'package:xiaodouzi_fr/core/storage/box_descriptor.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});

    // 桩 path_provider：单元测试无 platform channel，
    // 让 getApplicationDocumentsDirectory() 返回临时目录，buildDumpText 内部的
    // 磁盘扫描 + 笔记收集都拿到空结果。
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final tmpPath = Directory.systemTemp.createTempSync('fr_pp_').path;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return tmpPath;
        }
        if (call.method == 'getApplicationSupportDirectory' ||
            call.method == 'getTemporaryDirectory' ||
            call.method == 'getExternalStorageDirectory') {
          return tmpPath;
        }
        return null;
      },
    );
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fr_exporter_test');
    Hive.init(tempDir.path);
    StorageRegistry.register(BoxDescriptor<dynamic>(
      name: 'test_box',
      displayName: '测试',
      openUntyped: () => Hive.openBox('test_box'),
    ));
  });

  tearDown(() async {
    StorageRegistry.clear();
    await Hive.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('buildDumpText produces structured text', () async {
    final box = await Hive.openBox<dynamic>('test_box');
    await box.put('k1', 'v1');

    final r = await StorageExporter().buildDumpText();
    expect(r.text, contains('[meta]'));
    expect(r.text, contains('[hive:test_box]'));
    expect(r.text, contains('K:k1'));
    expect(r.text, contains('T:String'));
    expect(r.text, contains('V:v1'));
    expect(r.text, contains('# END_STORAGE_DUMP_V1'));
    expect(r.totalKeys, greaterThanOrEqualTo(1));
  });

  test('buildDumpText → importFromText round-trip is lossless', () async {
    final box = await Hive.openBox<dynamic>('test_box');
    await box.put('alpha', 'one');
    await box.put('beta', 'two');

    final r = await StorageExporter().buildDumpText();

    await box.clear();
    final imp = await StorageImporter(clearBeforeImport: true).importFromText(
      r.text,
    );
    expect(imp.errorCount, 0,
        reason: 'round-trip should produce zero errors, got: ${imp.errors}');

    final reopened = Hive.box<dynamic>('test_box');
    expect(reopened.get('alpha'), 'one');
    expect(reopened.get('beta'), 'two');
  });
}
