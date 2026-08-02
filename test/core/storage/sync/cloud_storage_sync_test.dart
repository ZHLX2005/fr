import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/api/api_response.dart';
import 'package:xiaodouzi_fr/api/goframe/kv/kv_endpoint.dart';
import 'package:xiaodouzi_fr/core/storage/sync/cloud_storage_sync.dart';

class _FakeKv implements KvOps {
  final List<String> stored;
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
    return ApiResponse(
      code: 0,
      message: 'OK',
      data: KvItem(key: key, value: '', expiresAt: null),
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
    return ApiResponse(code: 0, message: 'OK');
  }

  @override
  Future<ApiResponse<void>> delete(String key) async {
    lastDeleted = key;
    stored.remove(key);
    return ApiResponse(code: 0, message: 'OK');
  }

  @override
  Future<ApiResponse<KvListResult>> list({
    int limit = 50,
    int offset = 0,
  }) async {
    final items = stored
        .map((k) => KvItem(key: k, value: '', expiresAt: null))
        .toList();
    return ApiResponse(
      code: 0,
      message: 'OK',
      data: KvListResult(items: items, total: items.length),
    );
  }
}

void main() {
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
}
