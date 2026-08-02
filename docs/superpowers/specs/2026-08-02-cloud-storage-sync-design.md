# 云端存储同步（CloudStorageSync）设计

> 日期：2026-08-02
> 状态：已过设计评审，待写实现计划
> 关联：替换 `lib/core/storage/export/` 的文件导出/导入为后端 KV 同步

## 1. 背景与目标

当前本地存储（Hive boxes + SharedPreferences + 笔记文件）的备份/恢复走**文件**：
`StorageExporter.exportAll()` 写 `storage_dump_<ts>.txt` 到外部目录，`StorageImporter` 用
FilePicker 选文件读回。问题：文件要手动转移、跨设备麻烦、易丢失。

**目标**：不再落文件，直接用后端 `dev_ctr_hello`（GoFrame，`47.110.80.47:8988`）的 KV 服务：
登录拿 JWT → `set/get` KV，key 由用户自己命名，一份本地快照存一个 key。

后端栈与 fr 端封装**均已存在**，本设计只把"文件运输"换成"KV 运输"：

- 登录：`UserAuthService.login()`（GetIt 单例）→ JWT 写入 `SharedPrefsTokenStorage`
  （key `api_access_token`）。
- KV：`kvEndpointProvider`（Riverpod）→ `ApiClient` → `AuthInterceptor` 自动读同一 token
  注入 `Bearer`，`KvEndpoint` 走 `/api/v1/kv`。
- 序列化：`StorageExporter` 产 dump 文本 / `StorageImporter.importFromText(text)` 还原
  （二者已修通，是值钱的部分，保留）。

## 2. 后端接口契约（已存在，对接即用）

统一信封 `{code, message, data}`；`code=0` 成功，`50/51` 业务错误（HTTP 仍 200），
`401` 未登录（HTTP 也 401）。

| 接口 | 方法/路径 | 关键字段 |
|---|---|---|
| 登录 | `POST /api/v1/user/login` | req `{email,password}` → data `{token,userId}` |
| 我的信息 | `GET /api/v1/user/info` | data `{id,email,username,nickname,invitationCode}` |
| 设 KV | `POST /api/v1/kv` | req `{key,value,visibility?,ttl?}`（visibility 默认 private，ttl 默认 0）→ 同 (owner,key) upsert |
| 取 KV | `GET /api/v1/kv/:key` | data `{key,value,visibility,expires_at}` |
| 删 KV | `DELETE /api/v1/kv/:key` | 仅 owner 可删 |
| 列 KV | `GET /api/v1/kv?limit&offset` | data `{items:[{key,value,visibility,expires_at}],total}`，只列自己的 |

> 注：后端 skill 文档写 `:8080` 是占位，实际部署端口 `8988`，fr 的 `GoframeConfig.baseUrl`
> 与 `UserAuthService._baseUrl` 均已是 `http://47.110.80.47:8988`。

## 3. 命名空间约定

用户的 KV 空间按 owner 隔离但同 owner 内共享。为避免存储备份与未来其它 KV 用途混淆，
所有备份 key 统一加固定前缀：

```
真实 key = "fr_storage_backup:" + 用户输入的友好名
```

- 用户输入 `phone-aug` → 后端存 `fr_storage_backup:phone-aug`。
- 列表时 `kv.list` 过滤前缀、展示时剥前缀，用户只看到友好名。
- 前缀加/剥只在 `CloudStorageSync` 内部，UI 与后端都不感知。

## 4. 组件设计

### 4.1 新增 `lib/core/storage/sync/cloud_storage_sync.dart`

薄服务层，注入 `KvEndpoint`（可测），内部委托序列化给 `StorageExporter`/`StorageImporter`。

```dart
class CloudStorageSync {
  CloudStorageSync(this._kv);
  final KvEndpoint _kv;

  static const String prefix = 'fr_storage_backup:';

  /// 备份：本地全量 → dump 文本 → kv.set(prefix+name, text)
  /// 返回写入字节数 / 失败原因。
  Future<BackupResult> backup(String name, {void Function(ExportProgress)? onProgress});

  /// 恢复：kv.get(prefix+name) → importFromText(value, clearBeforeImport)
  Future<RestoreResult> restore(String name, {bool clearFirst = false,
      void Function(ImportProgress)? onProgress});

  /// 列已有备份友好名（过滤前缀、剥前缀）。
  Future<List<String>> listBackups();

  /// 删除一个备份。
  Future<bool> deleteBackup(String name);
}

class BackupResult { final bool ok; final int bytes; final String? error; }
class RestoreResult { final bool ok; final ImportResult? import; final String? error; }
```

- 内部用 `_realKey(name) => '$prefix$name'`。
- `backup`：`final r = await StorageExporter(...).buildDumpText(onProgress: ...)`；
  `r.text` 非空 → `await _kv.set(key: _realKey(name), value: r.text)`；按 `ApiResponse.code`
  判成败（`code==0` 成功；`50/51/-1` 失败，带 message）。
- `restore`：`final g = await _kv.get(_realKey(name))`；`code!=0 || data==null` → 失败；
  否则 `await StorageImporter(...).importFromText(g.data!.value, clearBeforeImport: clearFirst, onProgress: ...)`。
- `listBackups`：`final l = await _kv.list()`；`l.data.items` 过滤 `key.startsWith(prefix)`，
  剥前缀返回。
- `deleteBackup`：`await _kv.delete(_realKey(name))`；`code==0` 视为成功（删不存在的也回 0/404 视实现，按 message 区分）。

### 4.2 改造 `storage_exporter.dart`

- 抽出 `Future<ExportResult> buildDumpText({void Function(ExportProgress)? onProgress})`：
  原 `exportAll()` 里"拼文本"的正文（`_storage.init()` + `_discoverBoxNames()` + 逐 box 打开
  + meta + Hive + prefs + notes + footer），**不写文件**，
  返回 `ExportResult(text, totalKeys, totalSize, timestamp)`。
- **删除**：`_writeExportFile` / `_resolveExportBaseDir` / `path_provider` import / `dart:io` 中
  文件相关用法（`Platform` 仍用于 meta platform，保留 `dart:io` 若还需）。
- `ExportResult`：去掉 `filePath` 字段（不再落盘）。
- 原 `exportAll()` 删除（无其它调用方——仅 storage_analyze_demo 的 `_onExport` 用，本设计一并移除）。

### 4.3 `storage_importer.dart` 不动

`importFromText(text, {clearBeforeImport, onProgress})` 已是 restore 所需入口，签名兼容。
（注：上轮已修通解析与 typed 序列化。）

### 4.4 `lib/api/user/user_auth_service.dart` 加 `userInfo()`

```dart
Future<AuthResult> userInfo() async {
  final r = await _get('/user/info');   // 走带 token 的 GET
  return r;
}
```

- 用途：登录闸显示"已登录：<email/nickname>"，验证 token 仍有效（401 即失效）。
- 现有 `_post` 复用；新增一个 `_get(String path)` 走同样的信封解析。

### 4.5 改造 `lib/lab/demos/storage_analyze_demo.dart`

- 基类 `State` → `ConsumerState`（页面用 `ref.read(kvEndpointProvider)` 拿 `KvEndpoint` 构造
  `CloudStorageSync`；用 `ref.read(tokenManagerProvider)` 读登录态）。
- **新增第 4 个 tab「云同步」**（现有 `TabController(length:3)` → `length:4`）。
- **登录闸**（云同步 tab 主体，未登录时占满）：
  - email + password 输入 + 登录按钮 → `GetIt.instance<UserAuthService>().login(...)`。
  - 登录中转圈、失败显 `_loginError`。
  - 成功后 `setState` 刷新登录态。
- **已登录视图**：顶栏「已登录：<email>」+ 退出按钮（`tokenManager.clear()`）。
  email 来自 `userInfo()`（进 tab 时若 token 在则调一次取身份；401 视为未登录）。
- **同步面板**（仅已登录可点）：
  - 备份名输入框（友好名）。
  - 已有备份列表（`listBackups()`，单选）。
  - 三按钮：备份到云端 / 从云端恢复 / 删除备份。
  - 进度复用现有 `ExportProgress`/`ImportProgress` 的进度条样式。
- **删除**：AppBar actions 里的 `_onExport`（写文件）、`_onImport`（FilePicker）两按钮；
  以及该文件因此不再需要的 `file_picker` / `share_plus` / `path_provider` import
  （仅当本文件无其它用途时删 import；pubspec 依赖保留）。

## 5. 数据流

**备份**：输入名 `phone-aug` → `CloudStorageSync.backup("phone-aug")` →
`buildDumpText()` → `kv.set("fr_storage_backup:phone-aug", text)` → `POST /api/v1/kv`（upsert）→
刷新列表。

**恢复**：选中 `phone-aug` → 确认"清空后导入？" → `restore("phone-aug", clearFirst)` →
`kv.get("fr_storage_backup:phone-aug")` → `importFromText(text, clearBeforeImport)` →
写回 Hive/prefs/notes → 返回 `ImportResult` → `_loadStorageData()` 刷新本地视图。

**列表**：进云同步 tab → `listBackups()` → `kv.list()` → 过滤前缀 → 剥前缀展示。

## 6. 错误处理

| 情形 | 处理 |
|---|---|
| 未登录 / token 失效（401） | `AuthInterceptor` 试 refresh（当前无 refresh 实现 → 失败）→ 提示「登录已失效，请重新登录」+ 切回登录闸 |
| 网络错误（`code=-1`） | snackbar「网络错误：<message>」 |
| 业务错误（`code=50/51`，HTTP 200） | snackbar 显 `message` |
| dump 过大 | 不阻断（Postgres TEXT 可存 MB 级）；> 1MB 时备份前给轻提示 |
| restore 单条失败 | `importFromText` 已逐条 try/catch，统计进 `errorCount`，不中断整体 |
| 列表为空 | 空态提示「还没有云端备份，输入名称创建第一个」 |

## 7. 文件改动清单

| 操作 | 文件 | 说明 |
|---|---|---|
| NEW | `lib/core/storage/sync/cloud_storage_sync.dart` | 薄服务层（backup/restore/list/delete + 前缀管理） |
| EDIT | `lib/core/storage/export/storage_exporter.dart` | 抽 `buildDumpText()`，删文件写入与 `filePath` |
| EDIT | `lib/api/user/user_auth_service.dart` | 加 `userInfo()` + `_get` |
| EDIT | `lib/lab/demos/storage_analyze_demo.dart` | `ConsumerState` + 云同步 tab + 登录闸，删文件导出/导入按钮与多余 import |

不动：`storage_importer.dart`、`const_storage_export.dart`、`box_descriptor.dart`、
`storage_registry.dart`、`storage_manager.dart`、后端任何代码。

## 8. 测试

- **`CloudStorageSync` 单测**（纯 Dart，mock `KvEndpoint`）：
  - `backup("x")` → 验证 `set` 收到 key=`fr_storage_backup:x`、value 非空 dump。
  - `restore("x")` → 验证先 `get(prefix+x)`、再调 `importFromText`，传 `clearFirst`。
  - `listBackups()` → 给一组含前缀与不含前缀的 key，验证只回剥前缀的友好名。
  - `deleteBackup("x")` → 验证 `delete(prefix+x)`。
- **dump 往返**：`buildDumpText()` → `importFromText()` 在一个空 Hive+prefs 环境里能还原
  （复用上轮已修通的解析链路）。
- **手测**（真机/web）：注册→登录→备份 `test`→清本地→恢复 `test`→数据回来；未登录时同步按钮禁用。

## 9. 范围与非目标

- **不做**：增量同步、按 box 粒度同步、多版本备份历史、端到端加密（已有独立的 `e2ekv` 模块，
  不在本范围）、备份定时自动上传。
- 多设备同步：同账号同 key 天然生效（owner 隔离 + 同 key upsert），无需额外工作。
- 列表只显友好名（不显 size/时间——后端 `kv.list` 不回 `updatedAt`，避免逐条 get）。
