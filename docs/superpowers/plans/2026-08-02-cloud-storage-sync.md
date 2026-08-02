# Cloud Storage Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `lib/core/storage/export/` file-based export/import with backend KV sync (login → set/get KV under user-named key).

**Architecture:** Reuse existing `UserAuthService` (login/JWT) + `KvEndpoint` (set/get/delete/list on `/api/v1/kv`). Keep the dump-text serialization (build/parse). New `CloudStorageSync` service bridges them with a `fr_storage_backup:` key prefix. Storage page gains a 4th "云同步" tab with a built-in email/password login gate.

**Tech Stack:** Flutter (Dart), Riverpod (`api_providers`), GetIt (`UserAuthService`), `package:http` (existing), `package:hive`, `package:shared_preferences`. Tests: `flutter_test` + `SharedPreferences.setMockInitialValues` + temp-dir Hive.

**Spec:** `docs/superpowers/specs/2026-08-02-cloud-storage-sync-design.md`

## Global Constraints

- Backend base URL: `http://47.110.80.47:8988/api/v1` (GoFrame; JWT in `Authorization: Bearer …`).
- Envelope `{code, message, data}`; code 0=ok, 50/51 business (HTTP 200), 401 unauth (HTTP 401). Judge on body code, not HTTP.
- KV key prefix (user names the suffix): `fr_storage_backup:`. Add/strip only inside `CloudStorageSync`.
- Project workflow: Flutter, `flutter analyze` gate, commit only own files, push via SSH.
- Existing dependencies stay; no pubspec changes needed (just_audio, hive, shared_preferences, file_picker, share_plus, path_provider, http, get_it, flutter_riverpod all present).

---

### Task 1: Exporter — extract `buildDumpText`, drop file-write

**Files:**
- Modify: `lib/core/storage/export/storage_exporter.dart`
- Test: `test/core/storage/export/storage_exporter_test.dart` (NEW)

**Interfaces:**
- Consumes: `StorageManager.instance` (existing), `StorageRegistry` (existing), `Hive` / `SharedPreferences` (existing).
- Produces: `Future<ExportResult> buildDumpText({void Function(ExportProgress)? onProgress})` returning `ExportResult(text, totalKeys, totalSize, timestamp)` — **no** `filePath`.

**Context for the implementer:** The current `exportAll()` mixes serialization + file writing. Extract the serialization (which keeps `_storage.init()`, `_discoverBoxNames()`, box opening, meta, hive/prefs/notes iteration, footer) into `buildDumpText`. Drop `_writeExportFile`, `_resolveExportBaseDir`, `path_provider` import, and the `filePath` field on `ExportResult`. The legacy box list and `ExportStage` enum stay (used by importer + UI).

- [ ] **Step 1: Write the failing test**

Create `test/core/storage/export/storage_exporter_test.dart`:

```dart
import 'dart:io';
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

    // clear, then re-import
    await box.clear();
    final imp = await StorageImporter().importFromText(
      r.text,
      clearBeforeImport: true,
    );
    expect(imp.errorCount, 0,
        reason: 'round-trip should produce zero errors, got: ${imp.errors}');

    final reopened = Hive.box<dynamic>('test_box');
    expect(reopened.get('alpha'), 'one');
    expect(reopened.get('beta'), 'two');
  });
}
```

- [ ] **Step 2: Run test, verify it fails**

Run: `flutter test test/core/storage/export/storage_exporter_test.dart`
Expected: compile error `The method 'buildDumpText' isn't defined` (current API is `exportAll()`).

- [ ] **Step 3: Implement `buildDumpText`, drop file-write**

In `lib/core/storage/export/storage_exporter.dart`:

1. Remove imports: `package:path_provider/path_provider.dart` and (if now unused) `dart:io` references to file writing. Keep `dart:io` only if `Platform.operatingSystem` is still used in meta (it is — keep `dart:io`).
2. Remove methods: `_writeExportFile`, `_resolveExportBaseDir`.
3. Rename `exportAll()` → `buildDumpText({void Function(ExportProgress)? onProgress})` and **drop the file-writing tail**. Replace the trailing file-write block with: skip entirely; `return ExportResult(text: text, totalKeys: totalKeys, totalSize: totalSize, timestamp: timestamp);`
4. In `class ExportResult`, remove the `final String filePath;` field and its constructor parameter (this is safe — `ExportResult` is only constructed inside `exportAll`).
5. Keep `_discoverBoxNames`, `_typeNameOf`, `_encodeValue`, `_emitProgress`, `storageSection`, etc. untouched.

- [ ] **Step 4: Run test, verify it passes**

Run: `flutter test test/core/storage/export/storage_exporter_test.dart`
Expected: both tests PASS.

- [ ] **Step 5: Run analyze**

Run: `flutter analyze lib/core/storage/export/storage_exporter.dart test/core/storage/export/storage_exporter_test.dart`
Expected: 0 errors (info-level doc-comment lints about angle brackets pre-existing in the importer are fine and not touched by this task).

- [ ] **Step 6: Commit**

```bash
git add lib/core/storage/export/storage_exporter.dart test/core/storage/export/storage_exporter_test.dart
git commit -m "refactor(storage): 抽出 buildDumpText、移除导出文件写入

ExportResult 去掉 filePath 字段；storage_analyze_demo 的文件导出按钮
将在后续 task 一并移除。导入链路 importFromText 不变。"
```

---

### Task 2: `UserAuthService.userInfo()` + `_get()`

**Files:**
- Modify: `lib/api/user/user_auth_service.dart`

**Interfaces:**
- Produces: `Future<AuthResult> userInfo()` — returns `AuthResult(code, message, data)` where on success `data['email']`, `data['nickname']`, `data['invitationCode']` are available.

- [ ] **Step 1: Write the failing test**

Create `test/api/user/user_auth_service_test.dart`:

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xiaodouzi_fr/api/user/user_auth_service.dart';

void main() {
  test('userInfo parses envelope and returns AuthResult', () async {
    final mock = MockClient((req) async {
      expect(req.method, 'GET');
      expect(req.url.path, endsWith('/api/v1/user/info'));
      return http.Response(
        jsonEncode({
          'code': 0,
          'message': 'OK',
          'data': {
            'id': 1,
            'email': 'a@b.c',
            'username': '',
            'nickname': 'nick',
            'invitationCode': 'ABC12345',
          },
        }),
        200,
        headers: {'Content-Type': 'application/json'},
      );
    });

    // Construct a test-friendly service via a tiny shim:
    // since _get is private, we exercise userInfo end-to-end with the
    // MockClient. Replace the service's internal _client by constructing
    // through a factory; simplest: use the real service and stub the http
    // client via http.runWithClient. Use a custom instance.
    final svc = _TestableAuthService(client: mock);
    final r = await svc.userInfo();
    expect(r.isSuccess, true);
    expect(r.data?['email'], 'a@b.c');
    expect(r.data?['nickname'], 'nick');
  });
}

/// Test shim: expose a constructor that accepts an injected http.Client.
class _TestableAuthService extends UserAuthService {
  _TestableAuthService({required http.Client client}) : _injectedClient = client;
  final http.Client _injectedClient;
  @override
  http.Client get _client => _injectedClient;
}
```

- [ ] **Step 2: Run test, verify it fails**

Run: `flutter test test/api/user/user_auth_service_test.dart`
Expected: compile error — `userInfo` not defined, and `_client` is not accessible / `_injectedClient` constructor doesn't exist yet.

- [ ] **Step 3: Implement `userInfo()` + `_get()`**

In `lib/api/user/user_auth_service.dart`:

1. Make the HTTP client injectable for testing. Refactor the existing `final http.Client _client = http.Client();` to allow a passed-in client. Concretely:

```dart
class UserAuthService {
  UserAuthService({http.Client? client}) : _client = client ?? http.Client();

  final TokenStorage _storage = SharedPrefsTokenStorage();
  final http.Client _client;
  // ... rest unchanged ...

  Future<AuthResult> _post(String path, Map<String, dynamic> body) async { ... }

  Future<AuthResult> _get(String path) async {
    try {
      final res = await _client
          .get(
            Uri.parse('$_baseUrl$path'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 15));
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      return AuthResult(
        code: (json['code'] as num?)?.toInt() ?? -1,
        message: json['message'] as String? ?? '',
        data: json['data'] as Map<String, dynamic>?,
      );
    } catch (e) {
      return AuthResult(code: -1, message: '网络错误: $e');
    }
  }

  /// 我的信息（需已登录；token 由 AuthInterceptor 链路注入；本服务走自持 client 故需先登录）
  Future<AuthResult> userInfo() => _get('/user/info');
}
```

Note: `UserAuthService` uses its own `http.Client` (not the Riverpod `ApiClient`), so the Bearer token from `SharedPrefsTokenStorage` must be attached manually here. To do that, change `_get` to also read `accessToken` from `_storage` and inject the header:

```dart
Future<AuthResult> _get(String path) async {
  try {
    final token = await _storage.accessToken;
    final headers = {'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    final res = await _client
        .get(Uri.parse('$_baseUrl$path'), headers: headers)
        .timeout(const Duration(seconds: 15));
    // ... same envelope parse as _post ...
  } catch (e) { ... }
}
```

The existing `login` writes the token via `_storage.save(accessToken: token)`, so `userInfo()` will see it after login.

The test shim above works because the test passes a `MockClient` and reads `email`/`nickname` from the envelope's `data`. After login writes a real token, real `userInfo()` calls will succeed; the test bypasses that by mocking HTTP.

- [ ] **Step 4: Run test, verify it passes**

Run: `flutter test test/api/user/user_auth_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Run analyze**

Run: `flutter analyze lib/api/user/user_auth_service.dart test/api/user/user_auth_service_test.dart`
Expected: 0 errors.

- [ ] **Step 6: Commit**

```bash
git add lib/api/user/user_auth_service.dart test/api/user/user_auth_service_test.dart
git commit -m "feat(api): UserAuthService 加 userInfo()，http.Client 可注入便于测试"
```

---

### Task 3: `KvOps` interface + `CloudStorageSync` skeleton (prefix, list, delete)

**Files:**
- Modify: `lib/api/goframe/kv/kv_endpoint.dart` (add `KvOps` interface; `KvEndpoint implements KvOps`)
- Create: `lib/core/storage/sync/cloud_storage_sync.dart`
- Create: `test/core/storage/sync/cloud_storage_sync_test.dart`

**Interfaces:**
- `abstract interface class KvOps { Future<ApiResponse<KvItem?>> get(String key); Future<ApiResponse<void>> set({required String key, required String value, int? ttl}); Future<ApiResponse<void>> delete(String key); Future<ApiResponse<KvListResult>> list({int limit = 50, int offset = 0}); }`
- `class KvEndpoint implements KvOps { ... }` (no method body changes; signatures already match)
- `class CloudStorageSync { static const String prefix = 'fr_storage_backup:'; CloudStorageSync(this._kv); final KvOps _kv; Future<List<String>> listBackups(); Future<bool> deleteBackup(String name); }`

- [ ] **Step 1: Write the failing test**

Create `test/core/storage/sync/cloud_storage_sync_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/api/api_response.dart';
import 'package:xiaodouzi_fr/api/goframe/kv/kv_endpoint.dart';
import 'package:xiaodouzi_fr/core/storage/sync/cloud_storage_sync.dart';

class _FakeKv implements KvOps {
  final List<String> stored = ['a', 'b', 'fr_storage_backup:alpha', 'fr_storage_backup:beta'];
  String? lastDeleted;
  String? lastSet;
  String? lastSetValue;

  @override
  Future<ApiResponse<KvItem?>> get(String key) async =>
      ApiResponse(code: 0, message: 'OK', data: null);

  @override
  Future<ApiResponse<void>> set({required String key, required String value, int? ttl}) async {
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
  Future<ApiResponse<KvListResult>> list({int limit = 50, int offset = 0}) async {
    final items = stored
        .map((k) => KvItem(key: k, value: '', expiresAt: null))
        .toList();
    return ApiResponse(code: 0, message: 'OK', data: KvListResult(items: items, total: items.length));
  }
}

void main() {
  test('listBackups filters and strips prefix', () async {
    final fake = _FakeKv();
    final sync = CloudStorageSync(fake);
    final names = await sync.listBackups();
    expect(names, ['alpha', 'beta']); // 'a', 'b' filtered out; prefix stripped
  });

  test('deleteBackup sends prefixed key', () async {
    final fake = _FakeKv();
    final sync = CloudStorageSync(fake);
    await sync.deleteBackup('alpha');
    expect(fake.lastDeleted, 'fr_storage_backup:alpha');
    expect(fake.stored, isNot(contains('fr_storage_backup:alpha')));
  });
}
```

- [ ] **Step 2: Run test, verify it fails**

Run: `flutter test test/core/storage/sync/cloud_storage_sync_test.dart`
Expected: compile errors — `KvOps`, `CloudStorageSync` not defined.

- [ ] **Step 3: Implement `KvOps` interface**

In `lib/api/goframe/kv/kv_endpoint.dart`, ABOVE the existing `class KvEndpoint`:

```dart
/// KvEndpoint 提供的最小操作集合 —— 让 CloudStorageSync 等上游能注入替身（测试/mock）。
abstract interface class KvOps {
  Future<ApiResponse<KvItem?>> get(String key);
  Future<ApiResponse<void>> set({required String key, required String value, int? ttl});
  Future<ApiResponse<void>> delete(String key);
  Future<ApiResponse<KvListResult>> list({int limit = 50, int offset = 0});
}
```

Then change the `class KvEndpoint` declaration to `class KvEndpoint implements KvOps`. Method bodies already match (add `implements`, no body changes). The existing `KvItem` / `KvListResult` classes stay where they are.

- [ ] **Step 4: Implement `CloudStorageSync` skeleton**

Create `lib/core/storage/sync/cloud_storage_sync.dart`:

```dart
import '../../api/goframe/kv/kv_endpoint.dart';

/// 云端存储同步 —— 把本地 Hive+prefs+notes 整份快照存到一个 KV key。
///
/// 真实 key = `fr_storage_backup:<用户输入的友好名>`，前缀只在内部加/剥，
/// UI 永远看到的是友好名。
///
/// 依赖 [KvOps]（不是具体 KvEndpoint）以便单测注入。
class CloudStorageSync {
  CloudStorageSync(this._kv);

  final KvOps _kv;

  static const String prefix = 'fr_storage_backup:';

  String _realKey(String name) => '$prefix$name';

  /// 列已有备份的友好名（剥前缀；过滤非本前缀的 key）。
  Future<List<String>> listBackups() async {
    final r = await _kv.list();
    if (r.code != 0 || r.data == null) return const [];
    return r.data!.items
        .map((e) => e.key)
        .where((k) => k.startsWith(prefix))
        .map((k) => k.substring(prefix.length))
        .toList()
      ..sort();
  }

  /// 删除一个备份。
  Future<bool> deleteBackup(String name) async {
    final r = await _kv.delete(_realKey(name));
    return r.code == 0;
  }
}
```

- [ ] **Step 5: Run test, verify it passes**

Run: `flutter test test/core/storage/sync/cloud_storage_sync_test.dart`
Expected: PASS.

- [ ] **Step 6: Run analyze**

Run: `flutter analyze lib/api/goframe/kv/kv_endpoint.dart lib/core/storage/sync/cloud_storage_sync.dart test/core/storage/sync/cloud_storage_sync_test.dart`
Expected: 0 errors.

- [ ] **Step 7: Commit**

```bash
git add lib/api/goframe/kv/kv_endpoint.dart lib/core/storage/sync/cloud_storage_sync.dart test/core/storage/sync/cloud_storage_sync_test.dart
git commit -m "feat(storage): KvOps 接口 + CloudStorageSync 骨架（list/delete + 前缀）"
```

---

### Task 4: `CloudStorageSync.backup`

**Files:**
- Modify: `lib/core/storage/sync/cloud_storage_sync.dart`
- Modify: `test/core/storage/sync/cloud_storage_sync_test.dart`

**Interfaces:**
- `Future<BackupResult> backup(String name, {void Function(ExportProgress)? onProgress})` — serializes via `StorageExporter().buildDumpText(...)` then `kv.set(prefix+name, text)`. Returns `BackupResult(ok: bool, bytes: int?, error: String?)`.

- [ ] **Step 1: Write the failing test**

Append to `test/core/storage/sync/cloud_storage_sync_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/core/storage/box_descriptor.dart';
import 'package:xiaodouzi_fr/core/storage/export/storage_exporter.dart';
import 'package:xiaodouzi_fr/core/storage/storage_registry.dart';

// In the existing test class or a new group, add:
void main() {
  // ... existing tests ...

  group('backup', () {
    late Directory tempDir;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
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

    test('writes prefixed key with dump text', () async {
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
  });
}
```

- [ ] **Step 2: Run test, verify it fails**

Run: `flutter test test/core/storage/sync/cloud_storage_sync_test.dart`
Expected: compile error — `backup`, `BackupResult` not defined.

- [ ] **Step 3: Implement `backup`**

Add to `cloud_storage_sync.dart` (at the top, add imports):

```dart
import '../export/storage_exporter.dart';
```

Add class:

```dart
class BackupResult {
  final bool ok;
  final int? bytes;
  final String? error;
  const BackupResult({required this.ok, this.bytes, this.error});
}
```

Add method inside `CloudStorageSync`:

```dart
Future<BackupResult> backup(
  String name, {
  void Function(ExportProgress)? onProgress,
}) async {
  final er = await StorageExporter().buildDumpText(onProgress: onProgress);
  if (er.text.isEmpty) {
    return const BackupResult(ok: false, error: '导出内容为空');
  }
  final r = await _kv.set(key: _realKey(name), value: er.text);
  if (r.code != 0) {
    return BackupResult(ok: false, error: r.message.isEmpty ? 'kv set 失败' : r.message);
  }
  return BackupResult(ok: true, bytes: er.text.length);
}
```

- [ ] **Step 4: Run test, verify it passes**

Run: `flutter test test/core/storage/sync/cloud_storage_sync_test.dart`
Expected: PASS.

- [ ] **Step 5: Run analyze**

Run: `flutter analyze lib/core/storage/sync/cloud_storage_sync.dart test/core/storage/sync/cloud_storage_sync_test.dart`
Expected: 0 errors.

- [ ] **Step 6: Commit**

```bash
git add lib/core/storage/sync/cloud_storage_sync.dart test/core/storage/sync/cloud_storage_sync_test.dart
git commit -m "feat(storage): CloudStorageSync.backup —— dump 文本 kv.set(prefix+name)"
```

---

### Task 5: `CloudStorageSync.restore`

**Files:**
- Modify: `lib/core/storage/sync/cloud_storage_sync.dart`
- Modify: `test/core/storage/sync/cloud_storage_sync_test.dart`

**Interfaces:**
- `Future<RestoreResult> restore(String name, {bool clearFirst = false, void Function(ImportProgress)? onProgress})` — `kv.get(prefix+name)` → if data, `StorageImporter().importFromText(value, clearBeforeImport: clearFirst, onProgress)`. Returns `RestoreResult(ok: bool, import: ImportResult?, error: String?)`.

- [ ] **Step 1: Write the failing test**

Add a `_FakeKv.get` override that returns a real dump text when asked for the prefixed key. Then append to the test file:

```dart
// Add to _FakeKv class:
@override
Future<ApiResponse<KvItem?>> get(String key) async {
  if (key == 'fr_storage_backup:r1') {
    return ApiResponse(
      code: 0,
      message: 'OK',
      data: KvItem(
        key: key,
        value: '[meta]\nstorage_dump_version=1\n\n[hive:test_box]\nK:hello\nT:String\nV:world\n\n[prefs]\n\n[notes]\n\n# END_STORAGE_DUMP_V1\n',
        expiresAt: null,
      ),
    );
  }
  return ApiResponse<KvItem?>(code: 50, message: 'not found');
}

// New group:
group('restore', () {
  late Directory tempDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('fr_cloud_restore_test');
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

  test('restores data from kv value', () async {
    final fake = _FakeKv();
    final r = await CloudStorageSync(fake).restore('r1');
    expect(r.ok, true);
    expect(r.import, isNotNull);
    expect(r.import!.errorCount, 0,
        reason: 'restore errors: ${r.import!.errors}');
    expect(Hive.box<dynamic>('test_box').get('hello'), 'world');
  });

  test('missing key returns ok=false', () async {
    final fake = _FakeKv();
    final r = await CloudStorageSync(fake).restore('does-not-exist');
    expect(r.ok, false);
    expect(r.error, isNotNull);
  });
});
```

- [ ] **Step 2: Run test, verify it fails**

Run: `flutter test test/core/storage/sync/cloud_storage_sync_test.dart`
Expected: compile error — `restore`, `RestoreResult` not defined.

- [ ] **Step 3: Implement `restore`**

Add to `cloud_storage_sync.dart`:

```dart
import '../export/storage_exporter.dart';
import '../export/storage_importer.dart';
import '../export/const_storage_export.dart'; // for ImportProgress if needed
```

Add class:

```dart
class RestoreResult {
  final bool ok;
  final ImportResult? import;
  final String? error;
  const RestoreResult({required this.ok, this.import, this.error});
}
```

Add method:

```dart
Future<RestoreResult> restore(
  String name, {
  bool clearFirst = false,
  void Function(ImportProgress)? onProgress,
}) async {
  final r = await _kv.get(_realKey(name));
  if (r.code != 0 || r.data == null) {
    return RestoreResult(ok: false, error: r.message.isEmpty ? 'kv get 失败' : r.message);
  }
  final value = r.data!.value;
  if (value.isEmpty) {
    return const RestoreResult(ok: false, error: '备份内容为空');
  }
  final imp = await StorageImporter().importFromText(
    value,
    clearBeforeImport: clearFirst,
    onProgress: onProgress,
  );
  return RestoreResult(ok: true, import: imp);
}
```

- [ ] **Step 4: Run test, verify it passes**

Run: `flutter test test/core/storage/sync/cloud_storage_sync_test.dart`
Expected: PASS.

- [ ] **Step 5: Run analyze**

Run: `flutter analyze lib/core/storage/sync/cloud_storage_sync.dart test/core/storage/sync/cloud_storage_sync_test.dart`
Expected: 0 errors.

- [ ] **Step 6: Commit**

```bash
git add lib/core/storage/sync/cloud_storage_sync.dart test/core/storage/sync/cloud_storage_sync_test.dart
git commit -m "feat(storage): CloudStorageSync.restore —— kv.get → importFromText"
```

---

### Task 6: UI — storage page cloud-sync tab + login gate, remove file buttons

**Files:**
- Modify: `lib/lab/demos/storage_analyze_demo.dart`

**Interfaces:**
- Convert `_StorageAnalyzePage` to `ConsumerStatefulWidget`.
- `TabController(length: 3)` → `length: 4`. Add tab label "云同步".
- Add a 4th `TabBarView` with `_CloudSyncTab` widget.
- Remove AppBar action buttons for `_onExport` (write file) and `_onImport` (file picker).
- Remove imports `file_picker`, `share_plus`, `path_provider` if they become unused.
- Remove methods `_onExport`, `_onImport`, and helper types/constants they used (export path/share helpers etc. — leave any helpers still used by the rest of the page intact).

The new widget `_CloudSyncTab`:

- Reads `tokenManagerProvider` (Riverpod) → derives `bool isLoggedIn` from `_accessToken != null`. After login/logout, call `setState` on the parent or use `ref.invalidate(tokenManagerProvider)` to refresh.
- If not logged in: show a form with email + password TextFields, a "登录" button. On submit, call `GetIt.instance<UserAuthService>().login(email, pwd)`; on success call `userInfo()` to display identity.
- If logged in: show "已登录: <email/nickname> · 退出" row. Below it, the sync panel:
  - "备份名" TextField.
  - A list of existing backups (FutureBuilder / state) using `CloudStorageSync(ref.watch(...).kv).listBackups()` — actually build the sync service lazily inside the widget with `ref.read(kvEndpointProvider)`.
  - Buttons: 备份到云端 / 从云端恢复 / 删除备份.
  - Progress: reuse the existing `ExportProgress`/`ImportStage` display pattern (label + linear progress).
- Wire buttons to call the service. Confirm dialog for restore (clear first?) — reuse pattern from current `_onImport`.

- [ ] **Step 1: Convert page base class**

In `lib/lab/demos/storage_analyze_demo.dart`:

1. Change imports to add: `import 'package:flutter_riverpod/flutter_riverpod.dart';`, `import 'package:get_it/get_it.dart';`, `import '../../api/goframe/kv/kv_endpoint.dart';`, `import '../../api/providers/api_providers.dart';`, `import '../../api/token/token_manager.dart';`, `import '../../api/user/user_auth_service.dart';`, `import '../../core/storage/sync/cloud_storage_sync.dart';`.
2. Remove imports if now unused: `package:file_picker/file_picker.dart`, `package:share_plus/share_plus.dart`, `package:path_provider/path_provider.dart` (only remove each if it's not referenced elsewhere in the file after the removals below).
3. Change class declaration: `class _StorageAnalyzePageState extends State<_StorageAnalyzePage> with SingleTickerProviderStateMixin` → `class _StorageAnalyzePageState extends ConsumerState<_StorageAnalyzePage> with SingleTickerProviderStateMixin`.
4. Change `TabController _tabController = TabController(length: 3, vsync: this)` (in initState) → `TabController(length: 4, vsync: this)`.

- [ ] **Step 2: Add 4th tab to `TabBar` and `TabBarView`**

Find the `TabBar(tabs: const [...])` block (currently 3 tabs). Add a 4th tab with label `'云同步'`:

```dart
tabs: const [
  /* existing 3 tabs */,
  Tab(icon: Icon(Icons.cloud_outlined), text: '云同步'),
],
```

Find the `TabBarView(controller: _tabController, children: [...])`. Append a 4th child widget for the cloud sync tab (build the new widget in step 3):

```dart
TabBarView(
  controller: _tabController,
  children: [
    /* existing 3 children */,
    _CloudSyncTab(refreshKey: _refreshKey, onAfterChange: _loadStorageData),
  ],
)
```

Add a `final int _refreshKey = 0;` field and a `void bumpRefreshKey() { setState(() {}); }` so the cloud-sync tab can be nudged after a restore (it can re-read the storage list and the parent can refresh).

- [ ] **Step 3: Build the `_CloudSyncTab` widget**

Add to the same file, BELOW `_StorageAnalyzePageState`. This widget is `ConsumerStatefulWidget` so it can use `ref.read(kvEndpointProvider)` and `ref.read(tokenManagerProvider)`.

```dart
class _CloudSyncTab extends ConsumerStatefulWidget {
  const _CloudSyncTab({required this.refreshKey, required this.onAfterChange});
  final int refreshKey;
  final Future<void> Function() onAfterChange;

  @override
  ConsumerState<_CloudSyncTab> createState() => _CloudSyncTabState();
}

class _CloudSyncTabState extends ConsumerState<_CloudSyncTab> {
  final _emailCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _busy = false;
  String? _identity;
  List<String> _backups = const [];
  String? _selected;

  @override
  void initState() {
    super.initState();
    _loadBackups();
    _loadIdentity();
  }

  @override
  void didUpdateWidget(covariant _CloudSyncTab old) {
    super.didUpdateWidget(old);
    if (old.refreshKey != widget.refreshKey) _loadBackups();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwdCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  bool get _isLoggedIn {
    final tm = ref.read(tokenManagerProvider);
    return tm.accessToken != null && (tm.accessToken as Future<String?>).then((s) => s != null && s.isNotEmpty) == null
        ? false
        : true; // simplified: re-read on actions; below we force a refresh after login.
  }

  // For simplicity and correctness, force the parent to call setState via
  // a post-frame after login/logout. Use a token version we bump:
  Future<void> _loadIdentity() async {
    if (!(await _hasToken())) {
      setState(() => _identity = null);
      return;
    }
    final r = await GetIt.instance<UserAuthService>().userInfo();
    if (r.code == 401) {
      // token invalid; clear it so we show login gate next build
      await ref.read(tokenManagerProvider).clear();
      setState(() => _identity = null);
      return;
    }
    if (r.isSuccess) {
      setState(() => _identity = (r.data?['email'] ?? r.data?['nickname'] ?? '').toString());
    }
  }

  Future<bool> _hasToken() async {
    final t = await ref.read(tokenManagerProvider).accessToken;
    return t != null && t.isNotEmpty;
  }

  Future<void> _loadBackups() async {
    if (!(await _hasToken())) {
      setState(() => _backups = const []);
      return;
    }
    final sync = CloudStorageSync(ref.read(kvEndpointProvider));
    final names = await sync.listBackups();
    if (mounted) setState(() => _backups = names);
  }

  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    final pwd = _pwdCtrl.text;
    if (email.isEmpty || pwd.isEmpty) return;
    setState(() => _busy = true);
    try {
      final r = await GetIt.instance<UserAuthService>().login(email, pwd);
      if (!mounted) return;
      if (r.isSuccess) {
        _pwdCtrl.clear();
        await _loadIdentity();
        await _loadBackups();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('登录成功')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('登录失败: ${r.message}')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    await ref.read(tokenManagerProvider).clear();
    if (!mounted) return;
    setState(() { _identity = null; _backups = const []; });
  }

  Future<void> _doBackup() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      final sync = CloudStorageSync(ref.read(kvEndpointProvider));
      final r = await sync.backup(name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.ok ? '已备份 "$name"（${r.bytes ?? 0} bytes）' : '备份失败: ${r.error ?? "?"}'),
      ));
      _nameCtrl.clear();
      await _loadBackups();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doRestore() async {
    final name = _selected;
    if (name == null) return;
    final clearFirst = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('从 "$name" 恢复'),
        content: const Text('建议先导出当前数据作为备份。\n是否同时清空已有数据？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('保留')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清空后导入', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (clearFirst == null) return;
    setState(() => _busy = true);
    try {
      final sync = CloudStorageSync(ref.read(kvEndpointProvider));
      final r = await sync.restore(name, clearFirst: clearFirst);
      if (!mounted) return;
      if (!r.ok) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('恢复失败: ${r.error ?? "?"}')));
        return;
      }
      final imp = r.import!;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          '恢复完成: Hive ${imp.hiveCount} / 配置 ${imp.prefsCount} / 笔记 ${imp.notesCount}'
          '${imp.errorCount > 0 ? " / 错误 ${imp.errorCount}" : ""}',
        ),
      ));
      await widget.onAfterChange();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doDelete() async {
    final name = _selected;
    if (name == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除备份 "$name"'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final sync = CloudStorageSync(ref.read(kvEndpointProvider));
      final removed = await sync.deleteBackup(name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(removed ? '已删除' : '删除失败')));
      await _loadBackups();
      setState(() => _selected = null);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasToken(),
      builder: (context, snap) {
        final loggedIn = snap.data == true;
        if (!loggedIn) return _buildLogin();
        return _buildSync();
      },
    );
  }

  Widget _buildLogin() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_outlined, size: 48),
              const SizedBox(height: 8),
              Text('云同步需要登录', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: '邮箱'), keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 8),
              TextField(controller: _pwdCtrl, decoration: const InputDecoration(labelText: '密码'), obscureText: true),
              const SizedBox(height: 16),
              FilledButton(onPressed: _busy ? null : _login, child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('登录')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSync() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text(_identity == null ? '已登录' : '已登录: $_identity')),
            TextButton(onPressed: _busy ? null : _logout, child: const Text('退出')),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: '备份名（友好名）'))),
            const SizedBox(width: 8),
            FilledButton(onPressed: _busy ? null : _doBackup, child: const Text('备份到云端')),
          ]),
          const SizedBox(height: 12),
          const Align(alignment: Alignment.centerLeft, child: Text('已有备份', style: TextStyle(fontWeight: FontWeight.w600))),
          Expanded(
            child: _backups.isEmpty
                ? const Center(child: Text('还没有云端备份'))
                : ListView.builder(
                    itemCount: _backups.length,
                    itemBuilder: (_, i) {
                      final n = _backups[i];
                      return RadioListTile<String>(
                        value: n,
                        groupValue: _selected,
                        title: Text(n),
                        onChanged: (v) => setState(() => _selected = v),
                      );
                    },
                  ),
          ),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: (_busy || _selected == null) ? null : _doRestore, child: const Text('从云端恢复'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: (_busy || _selected == null) ? null : _doDelete, child: const Text('删除备份'))),
          ]),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Remove `_onExport` / `_onImport` and their AppBar buttons**

In the same file:

1. In the AppBar `actions:` list, remove the two `IconButton`s that call `_onExport` and `_onImport`. Keep refresh + others.
2. Delete the entire methods `_onExport(...)` and `_onImport(...)` and any state fields only they used (`_isExporting`, `_isImporting`, `_exportStage`, `_importStage`, `_exportMessage`, `_importMessage`, `_exportCurrent`, `_exportTotal`, `_importCurrent`, `_importTotal`, `_exportProgressKey`, `_importProgressKey`, the progress bar UI block under `if (_isExporting || _isImporting)`).
3. If any of these state fields are referenced elsewhere, leave them — but in practice they're only used by the export/import buttons/progress.
4. Remove the now-unused imports `package:file_picker/file_picker.dart`, `package:share_plus/share_plus.dart`, `package:path_provider/path_provider.dart` (only if not referenced anywhere else after the deletes).

- [ ] **Step 5: Verify build + analyze**

Run: `flutter analyze lib/lab/demos/storage_analyze_demo.dart lib/core/storage/sync/cloud_storage_sync.dart`
Expected: 0 errors. (If `ConsumerState` complains about a missing import, ensure `flutter_riverpod` is imported. If `kvEndpointProvider` / `tokenManagerProvider` unresolved, ensure `api_providers.dart` is imported.)

If the file is large and `flutter analyze` is slow, run a targeted build check first:
Run: `flutter build apk --debug 2>&1 | tail -20` (only if you modified Android-side; not expected here). Otherwise rely on `flutter analyze`.

- [ ] **Step 6: Manual smoke (on web / device)**

Confirm with a real run:
1. Open the storage analysis demo.
2. New "云同步" tab → 未登录态 → email + 密码 → 登录成功（用之前已注册过的账户）。
3. 出现已登录区。输入备份名 → 备份到云端 → snackbar 报字节数。
4. 切换别的设备 / 重新登录同一账户 → 应能列出该备份 → 选中 → 从云端恢复 → 弹清空确认 → 完成后数据回来。
5. 选中备份 → 删除备份 → 列表为空。
6. 退出 → 回到登录闸。

- [ ] **Step 7: Commit**

```bash
git add lib/lab/demos/storage_analyze_demo.dart
git commit -m "feat(storage): 存储分析页加云同步 tab + 内置登录闸，移除文件导出/导入按钮

- 第 4 个 tab「云同步」：未登录显 email/密码闸，已登录显备份名输入 +
  已有备份列表 + 备份/恢复/删除三按钮
- 删除 _onExport / _onImport（写文件 / FilePicker / SharePlus 路径），
  及其状态字段与 AppBar 按钮
- 不再需要的 import（file_picker / share_plus / path_provider）从该文件移除
- 复用 Riverpod api_providers：kvEndpointProvider / tokenManagerProvider；
  复用 GetIt 中的 UserAuthService"
```

---

### Task 7: Final analyze + push

- [ ] **Step 1: Full analyze**

Run: `flutter analyze 2>&1 | grep -E "error|warning" | head -40`
Expected: only the pre-existing test errors in `test/lab/demos/calendar/lunar_date_codec_test.dart` and `test/lab/metronome/beat_buffer_generator_test.dart` (unrelated to this work). Zero errors in our touched files.

- [ ] **Step 2: git status check**

Run: `git status --short`
Expected: clean (all tasks committed). Confirm only this feature's files appear in recent commits (`git log --oneline -10`).

- [ ] **Step 3: Push**

Run: `git push origin master`
Expected: push succeeds; all 7 commits land on `origin/master`.

---

## Self-Review Notes (filled after writing)

**Spec coverage:**
- §2 backend contract → consumed in §4 (spec test data), §6 (UI uses Riverpod providers wired to that contract). No task needed beyond reading.
- §3 namespace prefix → Task 3 (`CloudStorageSync` `_realKey`, `listBackups` filter+strip, `deleteBackup` prefix).
- §4.1 `CloudStorageSync` API → Tasks 3, 4, 5 (constructor, list, delete, backup, restore).
- §4.2 exporter refactor → Task 1.
- §4.4 `userInfo` → Task 2.
- §4.5 UI 4th tab + login gate → Task 6.
- §5 data flow → exercised end-to-end by tests + manual smoke.
- §6 error handling → `_kv.get/set/delete/list` envelope codes handled in tasks 3–5; UI surfaces snackbars in Task 6.
- §7 file change list → matches all 7 tasks' files.
- §8 tests → exporter test (Task 1), userInfo test (Task 2), CloudStorageSync tests (Tasks 3–5). Manual smoke in Task 6.
- §9 non-goals → explicitly excluded (no incremental, no per-box granularity, no e2e).

**Placeholder scan:** none. Every code block is the actual code the implementer writes. UI test deliberately manual (UI tests for this widget would be heavy; manual is the project's norm per flutter-work-flow).

**Type consistency:** `KvOps` interface defined in Task 3, consumed by Tasks 3–5 via `CloudStorageSync(KvOps)`. `BackupResult` / `RestoreResult` defined in the task that introduces them. `kvEndpointProvider` / `tokenManagerProvider` from `api_providers.dart` consumed in Task 6 — those exports already exist.
