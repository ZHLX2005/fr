import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/api/api_response.dart';
import 'package:xiaodouzi_fr/api/goframe/kv/kv_endpoint.dart';
import 'package:xiaodouzi_fr/core/storage/box_descriptor.dart';
import 'package:xiaodouzi_fr/core/storage/storage_registry.dart';
import 'package:xiaodouzi_fr/core/storage/sync/cloud_storage_sync.dart';

class _FakeKv implements KvOps {
  final List<String> stored;
  final Map<String, String> values = {};
  String? lastDeleted;
  String? lastSet;
  String? lastSetValue;

  _FakeKv({List<String>? initial})
      : stored = List.of(initial ?? const []);

  @override
  Future<ApiResponse<KvItem?>> get(String key) async {
    if (!stored.contains(key)) {
      return ApiResponse<KvItem?>(code: 50, message: 'not found');
    }
    final v = values[key] ?? '';
    return ApiResponse(
      code: 0,
      message: 'OK',
      data: KvItem(key: key, value: v, expiresAt: null),
    );
  }

  @override
  Future<ApiResponse<void>> set({
    required String key,
    required String value,
    int? ttl,
  }) async {
    lastSet = key;
    lastSetValue = value;
    if (!stored.contains(key)) stored.add(key);
    values[key] = value;
    return ApiResponse(code: 0, message: 'OK');
  }

  @override
  Future<ApiResponse<void>> delete(String key) async {
    lastDeleted = key;
    stored.remove(key);
    values.remove(key);
    return ApiResponse(code: 0, message: 'OK');
  }

  @override
  Future<ApiResponse<KvListResult>> list({
    int limit = 50,
    int offset = 0,
  }) async {
    final items = stored
        .map((k) => KvItem(key: k, value: values[k] ?? '', expiresAt: null))
        .toList();
    return ApiResponse(
      code: 0,
      message: 'OK',
      data: KvListResult(items: items, total: items.length),
    );
  }
}

void main() {
  // path_provider 桩（buildDumpText 内部会调 getApplicationDocumentsDirectory）
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final tmpPath = Directory.systemTemp.createTempSync('fr_pp_').path;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationDocumentsDirectory' ||
            call.method == 'getApplicationSupportDirectory' ||
            call.method == 'getTemporaryDirectory' ||
            call.method == 'getExternalStorageDirectory') {
          return tmpPath;
        }
        return null;
      },
    );
  });

  late Directory tempDir;
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fr_cloud_sync_test');
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

  test('listBackups filters and strips prefix', () async {
    final fake = _FakeKv(initial: [
      'a',
      'b',
      'fr_storage_backup:alpha',
      'fr_storage_backup:beta',
    ]);
    final sync = CloudStorageSync(fake);
    final names = await sync.listBackups();
    expect(names, ['alpha', 'beta']);
  });

  test('deleteBackup sends prefixed key', () async {
    final fake = _FakeKv(initial: ['fr_storage_backup:alpha']);
    final sync = CloudStorageSync(fake);
    final ok = await sync.deleteBackup('alpha');
    expect(ok, true);
    expect(fake.lastDeleted, 'fr_storage_backup:alpha');
    expect(fake.stored, isNot(contains('fr_storage_backup:alpha')));
  });

  test('backup writes prefixed key with dump text', () async {
    final fake = _FakeKv();
    final box = await Hive.openBox<dynamic>('test_box');
    await box.put('k', 'v');

    final r = await CloudStorageSync(fake).backup('myphone');
    expect(r.ok, true);
    expect(fake.lastSet, 'fr_storage_backup:myphone');
    expect(fake.lastSetValue, isNotEmpty);
    expect(fake.lastSetValue, contains('[hive:test_box]'));
    expect(fake.lastSetValue, contains('K:k'));
  });

  test('restore reads prefixed key and writes to local Hive', () async {
    // 先做一次 backup 拿到合法 dump 文本，存进 fake 模拟云端。
    final fake = _FakeKv();
    final box = await Hive.openBox<dynamic>('test_box');
    await box.put('hello', 'world');
    final b = await CloudStorageSync(fake).backup('r1');
    expect(b.ok, true);

    // 清空本地，再 restore —— 应该恢复 hello=world。
    await box.clear();
    final r = await CloudStorageSync(fake).restore('r1');
    expect(r.ok, true);
    expect(r.import, isNotNull);
    expect(r.import!.errorCount, 0,
        reason: 'restore errors: ${r.import!.errors}');
    expect(Hive.box<dynamic>('test_box').get('hello'), 'world');
  });

  test('restore missing key returns ok=false', () async {
    final fake = _FakeKv();
    final r = await CloudStorageSync(fake).restore('does-not-exist');
    expect(r.ok, false);
    expect(r.error, isNotNull);
  });
}
