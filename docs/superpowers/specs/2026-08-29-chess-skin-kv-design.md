# chess 皮肤 KV 远程加载 — 设计文档

| 字段 | 值 |
| --- | --- |
| 日期 | 2026-08-29 |
| 状态 | ⏳ 待用户审阅（**重大方案变更：去掉 KV，改 hardcode + File API public download**） |
| 关联模块 | `lib/core/chess/` |
| 关联 File 后端 | `lib/api/goframe/file/file_endpoint.dart`（下载走公共 URL） |
| 决策点 | **修订方案**：File API public download + dart 源 hardcode 元数据 |

---

## ⚠️ 0. 设计变更公告（2026-08-29 用户决策）

**实测后发现：**

| 后端接口 | 匿名访问 | 结果 |
| --- | --- | --- |
| `POST /api/v1/kv` | ❌ 401 | 强制 Authorization header |
| `GET /api/v1/kv/:key` | ❌ 401 | 强制 Authorization header |
| `GET /api/v1/kv (list)` | ❌ 401 | 强制 Authorization header |
| `GET /api/v1/files (list)` | ✅ 200 OK | **public anonymous access** |
| `GET /files/:fileId` | ✅ 200 OK | **返回 webp 二进制，无 token** |

**结论：**
- `--visibility=public` 的 KV 仅控制已登录用户间可见性，**不豁免认证**
- File download URL（`http://<baseUrl>/files/<fileId>`）**真正 public anonymous**

**用户决策（2026-08-29）："或者 kv 元数据在这写死"**——把 8 套皮肤元数据（skinId / displayName / fileId × 12）**写死在 `lib/core/chess/skins/chess_skin_meta.dart` const**，完全跳过 KV 拉取路径。

**这一改动让 spec 实质简化成"纯客户端常量 + File API public 下载"**：
- 不需要 KV 后端协议
- 不需要 list / set / TTL / visibility 后端语义
- 不需要并发覆盖 / CAS lock
- 客户端冷启**无 token 也能看到 8 套皮肤**

**代价**：
- 添加新皮肤 / 更新 file_id → 必须发布新版本客户端（file_id 是 const 内联）
- 只支持"已有 file_id 字典"的皮肤列表；动态上传皮肤不在 v1 范围

## 1. 一句话设计（修订后）

**8 套皮肤 metadata = `lib/core/chess/skins/chess_skin_meta.dart` 中的 `const List<ChessSkinMeta>`**（编译期 hardcode）。
每张图的二进制 = 通过公开 URL `http://<baseUrl>/files/<fileId>` 拉取（无 token，匿名）。

**File_id 来源**（一次性流程，由用户在 `taskget` 流程里执行）：
1. 登录 kvcli 后台账号（uid=7 / token 存 `~/.kvcli/config.json`）
2. 跑上传脚本（`scripts/upload_chess_skins.dart`）：
   - 扫 `D:\DevProjects\my\test\image\chess\2\` 7 个子目录（每个 = 1 套皮肤）
   - 每个子目录 12 张 webp → `FileEndpoint.uploadByKey(...)` → 拿 file_id
   - 输出 `Map<skinId, Map<pieceKey, fileId>>` JSON 到 stdout
3. 用户把 JSON 交给 Claude，Claude 把它嵌入到 dart 源中
4. **后续添加皮肤必须重做 1+2+3 步骤 + 发布新版本**

## 2. 数据结构 — const 内联

```
lib/core/chess/skins/
├── chess_skin.dart                  ← 已有 interface + ChessSkinBundle（保留）
├── chess_skin_meta.dart             ← 新：ChessSkinMeta + FileRef + const 8 套 array
├── file_resolver.dart               ← 新：PublicFileResolver 直接拼 /files/<id> URL
├── remote_chess_skin.dart           ← 新：RemoteChessSkin implements ChessSkin
└── README.md
```

### chess_skin_meta.dart 的核心结构

```dart
// File_id 是 32-hex 字符串，由 upload 阶段固化进版本。
// 例：
// const _kFileIdsStaunty = <String, String>{
//   'wK': '4f4849d8b566a39d33a1f70216b4f0c8',
//   'wQ': '...',
//   ...
// };
//
// 这些 file_id 通过以下方式获得：
//   1. 登录 kvcli，账号 token 存 ~/.kvcli/config.json
//   2. 跑 scripts/upload_chess_skins.dart 上传 12 × 8 = 96 张 webp
//   3. 脚本输出 JSON：{ 'staunty': { 'wK': '<id>', ... } }
//   4. 把 JSON 嵌入本文件作为 const

const Map<String, Map<String, String>> kHardcodedChessSkins = {
  'staunty': { 'wK': '...', 'wQ': '...', ... 12 个 },
  'classic-wood': { 'wK': '...', ... },
  ...
};

const List<ChessSkinMeta> kChessSkinsCatalog = [
  ChessSkinMeta(
    id: 'staunty',
    displayName: '经典 Staunty',
    pieces: {
      'wK': FileRef(fileId: '...', fileName: 'wK.webp', sizeBytes: 4096, contentType: 'image/webp'),
      ...
    },
  ),
  ...
];
```

> **注意**：file_id 是 32-hex MD5 风格字符串。看后端 file list 返回：
> `"fileId":"4f4849d8b566a39d33a1f70216b4f0c8"`——32 字符 hex，不是 UUID。这是后端选用的格式。

## 3. 下载协议（客户端核心流程）

### 3.1 FileResolver

```dart
// lib/core/chess/skins/file_resolver.dart

abstract class FileResolver {
  /// 给一个 file_id，返回稳定的 HTTP(s) URL 给 cached_network_image。
  String url(String fileId);
}

/// 直接拼公开 URL，**不需要任何认证**。
class PublicFileResolver implements FileResolver {
  PublicFileResolver({required this.baseUrl}); // baseUrl = 'http://47.110.80.47:8988'
  
  @override
  String url(String fileId) {
    // 实测：用 HTTP HEAD 会返回 404，但 GET 直接返回 webp
    // — 后端路由用 GET-only 实现。
    return '$baseUrl/files/$fileId';
  }
}
```

### 3.2 RemoteChessSkin

```dart
// lib/core/chess/skins/remote_chess_skin.dart

class RemoteChessSkin implements ChessSkin {
  RemoteChessSkin({required this.meta, required this.fileResolver});
  final ChessSkinMeta meta;
  final FileResolver fileResolver;

  @override
  Map<String, ImageProvider> get pieces => {
    for (final entry in meta.pieces.entries)
      entry.key: CachedNetworkImage(fileResolver.url(entry.value.fileId)),
  };

  @override
  ImageProvider? get boardBackground =>
    meta.boardBackground == null
      ? null
      : CachedNetworkImage(fileResolver.url(meta.boardBackground!.fileId));
}
```

### 3.3 ChessSkinBundle 接入

```dart
// lib/core/chess/skins/chess_skin.dart (existing, add method)

abstract class ChessSkinBundle {
  static const Map<String, ChessSkin> _registry = {
    'default': ChessDefaultSkin(),
  };

  static Map<String, ChessSkin> get all => Map.unmodifiable(_registry);

  static ChessSkin byId(String id) => _registry[id] ?? _registry['default']!;

  /// v1 硬编码：从 const kChessSkinsCatalog 构造注册表。
  /// 调用方不需要 await——纯同步 const 构造。
  static void registerHardcoded() {
    for (final meta in kChessSkinsCatalog) {
      final skin = RemoteChessSkin(meta: meta, fileResolver: const PublicFileResolver(baseUrl: ...));
      (_registry as Map<String, ChessSkin>)[meta.id] = skin;
    }
  }
}
```

> **注意**：v1 中 `_registry` 不再是真正的 `const Map`——改为 `static Map<String, ChessSkin>`，通过 `registerHardcoded()` 一次性构建。这样 const 字段（file_id 字典）和 mutable registry 解耦。

### 3.4 客户端缓存策略

- `cached_network_image` 自带 7 天磁盘缓存（默认）+ 内存 LRU
- 无需自建缓存；无 token；404 / 网络失败自动 fallback 到 unicode 字符

### 3.5 启动拉取（**已不需要**）

v1 完全是**静态 const 加载**：没有 network round-trip 拉元数据。客户端启动 → 同步读 `kChessSkinsCatalog` → 构造 `RemoteChessSkin` 实例 → 用 `CachedNetworkImage` 异步渲染。

---

## 4. 上传协议（一次性流程，用户用 taskget 跑）

> 上传需**登录**，但只在脚本中一次性发生。最终客户端**无 token 也能跑**。

### 4.1 上传脚本骨架（用户在 `taskget` 流程里实现）

`scripts/upload_chess_skins.dart`（pubspec scripts/dev 模式）：

```dart
Future<Map<String, Map<String, String>>> uploadChessSkins({
  required String sourceDir, // 'D:/DevProjects/my/test/image/chess/2'
}) async {
  final fileEndpoint = FileEndpoint(apiClient); // 走现有 ApiClient + token
  final pieceToKey = {
    '00_white_king': 'wK',
    '01_white_queen': 'wQ',
    '02_white_rook': 'wR',
    '03_white_bishop': 'wB',
    '04_white_knight': 'wN',
    '05_white_pawn': 'wp',
    '06_black_king': 'bK',
    '07_black_queen': 'bQ',
    '08_black_rook': 'bR',
    '09_black_bishop': 'bB',
    '10_black_knight': 'bN',
    '11_black_pawn': 'bp',
  };

  final skinDirs = Directory(sourceDir).listSync().whereType<Directory>();
  final out = <String, Map<String, String>>{};

  for (final dir in skinDirs) {
    final skinId = p.basename(dir.path);
    final pieces = <String, String>{};
    for (final file in dir.listSync().whereType<File>()) {
      final basename = p.basenameWithoutExtension(file.path);
      final pieceKey = pieceToKey[basename];
      if (pieceKey == null) continue; // 跳过 _preview_grid.webp / _full_transparent.webp
      final bytes = await file.readAsBytes();
      final resp = await fileEndpoint.uploadByKey(
        key: 'chess_skin/$skinId/$pieceKey',
        fileName: '${basename}.webp',
        bytes: bytes,
      );
      if (resp.code != 0) throw 'upload ${file.path} → ${resp.message}';
      pieces[pieceKey] = resp.data!.id;
    }
    out[skinId] = pieces;
  }
  return out;
}

void main() async {
  final r = await uploadChessSkins(sourceDir: 'D:/DevProjects/my/test/image/chess/2');
  print(jsonEncode(r)); // 输出到 stdout → 给 Claude 嵌入 dart
}
```

### 4.2 实际 user taskget 流程

1. 用户在 `taskget` 里 run 上传脚本
2. 96 张图上传完成（约 2.6MB × 96 = ... 实际平均 30KB × 96 ≈ ~3MB 总流量）
3. 脚本输出 JSON：`{ "1": { "wK": "...", ... 12 个 }, "2": {...}, ... 7 套 }`
4. 用户把 JSON 提供给 Claude
5. Claude 把 JSON 嵌入 `chess_skin_meta.dart` 的 `kHardcodedChessSkins` / `kChessSkinsCatalog`
6. 后端不需要任何改动

---

## 5. 客户端组件图

```
lib/core/chess/skins/
├── chess_skin.dart              ← 已存在：interface + ChessDefaultSkin + ChessSkinBundle
├── chess_skin_meta.dart         ← 新：ChessSkinMeta + FileRef + const 8 套 catalog (with file_ids)
├── file_resolver.dart           ← 新：FileResolver + PublicFileResolver（拼 /files/<id>）
├── remote_chess_skin.dart       ← 新：RemoteChessSkin implements ChessSkin
└── README.md                    ← 更新："皮肤来源硬编码 + File API 匿名 download"
```

### 依赖图

```
ChessSkinBundle.registerHardcoded() (existing, modified to be mutable)
    ├── ChessDefaultSkin (existing)         → fallback
    └── RemoteChessSkin × 8 (new)
          └── meta = kChessSkinsCatalog[i]  // const
                └── piece.fileId          // const 字符串
                       └→ PublicFileResolver.url(fileId) → 'http://.../files/<fileId>'
                              └→ CachedNetworkImage (cached_network_image)

kChessSkinsCatalog (new const list)
    ├── 'staunty' → 12 fileIds
    ├── 'classic-wood' → ...
    └── (8 套)
```

无 KV 依赖、无 token 依赖、无网络拉取 round-trip。

---

## 6. 测试策略

| 类型 | 覆盖 | 方式 |
| --- | --- | --- |
| 模型 | `ChessSkinMeta.fromJson/toJson` 往返 + 12-key 完整性 + pieceId 32-hex regex | 单元测试 |
| Hardcode catalog | `kChessSkinsCatalog` 长度 == 8, 每套 pieces 12-key 完整 + file_id 是 32-hex | 单元测试 |
| FileResolver | `PublicFileResolver.url(id) == '$baseUrl/files/$id'` | 单元测试 |
| RemoteChessSkin | 注入 fake meta + fake resolver，验证 pieces[n].image 是 CachedNetworkImage 且 url 正确 | 单元测试 |
| Bundle 注册 | `ChessSkinBundle.registerHardcoded()` 后 `byId('staunty') != null` 且 equals 来自 const catalog | 单元测试 |
| 错误路径 | file 404 → `CachedNetworkImage` 自动 fallback 到 error widget | UI 集成测试 |

测试用 fake URLs + fake metas，不依赖真实后端。

---

## 7. 风险 + 边界

| 风险 | 缓解 |
| --- | --- |
| `file_id` 在版本中固化，热更新皮肤需发新版本 | v1 接受；如果未来需要热更新，把 catalog 从 const 改成"const + 后端 delta 更新" |
| 后端 `Files` 路由被改名 | FileResolver 抽象：换实现不用改业务代码 |
| 后端 `Files` 改成需要认证 | 重新接入 `FileEndpoint.metadata` + token（彻底回滚方案） |
| File 上传后被删除 | CachedNetworkImage 缓存还在；下次清理后显示 broken image；UI 端 → 自动 fallback (图片 widget 树 chessSkinIsComplete 检查) |
| 用户的 7 套图像命名重复（`1/`, `2/`, ...）而非有意义的 `staunty/`、`classical/` 等 | 上传脚本允许 `dir.name` 作为 skinId；用户可改皮肤目录名后重传 |
| 图片 MIME 实际是 webp 但 metadata 误标 image/png | UI 端从 `meta.pieces[k].contentType` 读，匹配不上时记录错误 + fallback |
| `file_id` 是 MD5 风格 32-hex 而非 UUID | 新增常量 `kFileIdPattern = RegExp(r'^[a-f0-9]{32}$')` 校验 |

---

## 8. 不动的范围

- ✅ **不修改**后端 Go 任何代码
- ✅ **不修改** `KvEndpoint` —— 它与 chess 皮肤无关
- ✅ **不修改** `ApiClient` / `AuthInterceptor` 链
- ✅ **不修改** `cached_network_image` 配置
- ✅ **不修改**棋盘颜色策略（`context.chessColors`）—— 棋盘底图走 `meta.boardBackground.fileId`，可选
- ⚠️ **小改** `chess_skin.dart` 中 `ChessSkinBundle`：添加 `registerHardcoded()` 入口 + `_registry` 改为 mutable Map

---

## 9. 实施拆解（前置 writing-plans）

预计任务清单：

1. **用户提供 96 个 file_id**（user taskget 跑上传脚本，输出 JSON 后交给 Claude）
2. `lib/core/chess/skins/chess_skin_meta.dart` — `ChessSkinMeta` + `FileRef` + const catalog（嵌入 96 个 file_id）
3. `lib/core/chess/skins/file_resolver.dart` — `PublicFileResolver.baseUrl` 配 `http://47.110.80.47:8988`
4. `lib/core/chess/skins/remote_chess_skin.dart` — `RemoteChessSkin implements ChessSkin`
5. `lib/core/chess/skins/chess_skin.dart` —— `ChessSkinBundle._registry` 改 mutable + 加 `registerHardcoded()` 方法
6. `test/core/chess/chess_skin_meta_test.dart` — 模型 + catalog 完整性
7. `test/core/chess/remote_chess_skin_test.dart` — 注入 fake meta 验证 piece → URL
8. `test/core/chess/file_resolver_test.dart` — PublicFileResolver URL 拼接
9. 更新 `lib/core/chess/skins/README.md` —— "皮肤来源：File API public download + const catalog"

### 库依赖（pubspec.yaml）

无新增依赖。

| 用途 | 现有依赖 |
|---|---|
| File 客户端 | `lib/api/goframe/file/file_endpoint.dart` ✓ |
| 图片缓存 | `cached_network_image: ^3.4.1` ✓ |
| HTTP | `http: ^1.2.2` ✓（用于 PublicFileResolver 直拼 URL 时不需要，但保留其他用途） |

---

## 10. 决策记录

| 决策 | 选定 | 原因 | 拒绝方案 |
| --- | --- | --- | --- |
| KV 元数据存哪 | **客户端 dart const**（hardcode） | KV 强制 auth；hardcode + File public 跳过 auth（实测 401 vs 200） | KV only（401）/ ZIP（粒度差）/ 后端改路由（不在本 spec） |
| File 下载怎么走 | 公开 URL `/files/<id>` | 实测无 token 可 GET webp 二进制 | `FileEndpoint.metadata`（需 token） |
| 客户端是否要 login | **否** | File API public + dart const 完全够 | 强制登录体验差 |
| 新加皮肤 | 改 dart const + 发版 | v1 接受；用户/文档维护者承担 | 动态 KV 拉（被 KV 401 阻断） |
| Cache 策略 | `cached_network_image` 默认 7 天磁盘 + LRU 内存 | 已有依赖 | Hive manual cache（多余） |
| `Files` 路由失败 fallback | UI 显示 broken image / 棋盘单色 | 罕见；保留 default 棋盘双格 | 跨层重试 |

---

**待用户审阅** → 用户批准 → 转入 `superpowers:writing-plans` 产出实施计划 → 实施。
