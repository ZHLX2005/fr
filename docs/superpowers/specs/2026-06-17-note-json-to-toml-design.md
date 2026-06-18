# `lib/core/note` 持久化层：JSON → TOML

> **状态**：待审核
> **日期**：2026-06-17
> **范围**：仅 `lib/core/note/persistence/`，不动领域层 / 渲染层 / 后端

---

## 1. 目标

把笔记文件的**存储格式**从 JSON 改为 TOML，让"存储格式"与"前后端传输格式"统一。

### 不做什么

- **不修改后端** `dev_ctr_hello/lib/ai/*`（用户明确约束）
- **不改领域层** `lib/core/note/core/*`（`Block` / `BlockType` / `RichText` / `BlockCodec` 保持不变）
- **不改渲染层** `lib/core/note/widget/*`
- **不改门面 API** `NoteFactory` 的公开方法签名（`saveNote/loadNote/listNotes/...` 全部不变）

## 2. 动机

1. **传输与存储统一**：后端 API 已用 TOML（`api/ai/v1/ai.go:49` `articleToml`）。前端落地也用 TOML 后，"前端给后端"零转换摩擦。
2. **行级可读性**：TOML 的 `[[blocks]]` 是平铺行级结构，`git diff` 友好，便于用 `sed/awk/grep` 快速定位单个块——JSON 需层层递归解析。
3. **AI diff 展示**：用户在前端编辑后，可直接复用后端返回的 `Diff` 字段做可视化，无需 JSON↔文本二次转换。

## 3. 现状（已通过实际搜索确认）

- **JSON 编解码只在 1 个文件**：`lib/core/note/persistence/note_repository.dart`，共 6 处（`:1/:40/:63/:76/:171/:173/:180/:189/:193`）
- **领域层产出 `Map<String, dynamic>`**：`BlockCodec.encode(block)` 已返回 Map——TOML 库可直接吃 Map，**无缝衔接**
- **上层引用面**：9 个文件通过 `NoteFactory` 公开 API 访问（`main.dart` + `storage_analyze_demo.dart` + `block_editor_demo/*` 7 个），全部只依赖方法签名，**0 改动**
- **无测试**：项目无 `test/` 目录
- **无孤儿/死代码**：`lib/core/note` 内 0 处 `TODO/FIXME/@deprecated`
- **无现成 TOML 依赖**：`pubspec.yaml` 未声明 `toml` 包
- **无 `.json` 测试数据**：仓库内无笔记数据文件

## 4. 决策记录

| 决策点 | 选择 | 理由 |
|---|---|---|
| TOML 库 | **`toml` 包**（pub.dev） | 成熟、双向（parse + encode）、支持 TOML 1.0 || 老数据迁移 | **app 内自动迁移** | 升级后老用户无感 |
| 迁移触发时机 | **首次访问 notes 目录时**（懒触发） | 避免冷启动阻塞 |
| 迁移失败策略 | **保留原 `.json` + 日志告警** | 不丢数据，下次可重试 |
| 文件后缀 | `.toml`（替换 `.json`） | 语义清晰 |
| `BlockCodec` | **不动** | 它已是 `Map` 中介，与文件格式解耦 |
| `storage_analyze_demo.dart` | **保留**，不删 demo | 它是运行时功能页；改 TOML 后 API 不变照样能跑 |

## 5. 架构

### 5.1 分层（改动前后对比）

```
改动前：
  NoteRepository
    └─ BlockCodec.encode(block) → Map
    └─ jsonEncode(Map) → String  ← JSON 边界
    └─ writeString → {id}.json

改动后：
  NoteRepository
    └─ BlockCodec.encode(block) → Map        ← 不变
    └─ TomlCodec.encode(Map) → String        ← 新增 TOML 边界
    └─ writeString → {id}.toml
```

**关键不变量**：`BlockCodec` 继续做 `Block ↔ Map`，新引入的 TOML 转换只在**仓库 IO 边界**发生。领域层永远不知道有 TOML。

### 5.2 新增组件

#### `TomlCodec`（新增，放 `persistence/toml_codec.dart`）

单一职责：`Map<String, dynamic> ↔ TOML 字符串`。

```dart
/// persistence/toml_codec.dart
///
/// Block Map ↔ TOML 字符串 的编解码器。
/// 仅在 NoteRepository 的 IO 边界使用，领域层不感知。
class TomlCodec {
  /// Map → TOML 字符串
  String encode(Map<String, dynamic> map);

  /// TOML 字符串 → Map
  Map<String, dynamic> decode(String toml);
}
```

**实现**：薄包装 `toml` 包的 `TomlDocument.fromMap(...).toString()` 与 `TomlDocument.parse(...).toMap()`。

#### `NoteMigration`（新增，放 `persistence/note_migration.dart`）

单一职责：把老 `.json` 笔记迁移为 `.toml`。

```dart
/// persistence/note_migration.dart
///
/// 一次性迁移：扫描 notes/ 下的 *.json，逐个转写为 *.toml。
/// 在 NoteRepository 首次访问目录时懒触发（idempotent）。
class NoteMigration {
  final BlockCodec _codec;

  NoteMigration(this._codec);

  /// 返回迁移的笔记数（0 = 无需迁移）。
  /// 失败的文件保留原样，仅记录日志，不抛异常。
  Future<int> migrateIfNeeded(Directory notesDir);
}
```

**幂等性**：迁移成功的 `.json` 才删除；失败保留。下次进入再试。

### 5.3 改动组件

#### `NoteRepository`（改 `persistence/note_repository.dart`）

| 行号 | 改动 |
|---|---|
| `:1` | `import 'dart:convert';` → `import 'package:toml/toml.dart';`（或经 `TomlCodec`） |
| `:40` | 注释 `.json` → `.toml` |
| `:63` | `endsWith('.json')` → `endsWith('.toml')` |
| `:76` | `jsonDecode(...)` → `TomlCodec.decode(...)` |
| `:171` | `{block.id}.json` → `{block.id}.toml` |
| `:173` | `jsonEncode(_codec.encode(block))` → `TomlCodec.encode(_codec.encode(block))` |
| `:180` | `{id}.json` → `{id}.toml` |
| `:189` | `{id}.json` → `{id}.toml` |
| `:193` | `jsonDecode(...)` → `TomlCodec.decode(...)` |

**构造函数改动**：增加迁移触发。

```dart
class NoteRepository {
  final BlockCodec _codec;
  final TomlCodec _tomlCodec;          // 新增
  bool _migrated = false;              // 进程内只迁移一次

  NoteRepository(this._codec) : _tomlCodec = TomlCodec();

  Future<Directory> _getNotesDir() async {
    final dir = ...;
    if (!_migrated) {
      await NoteMigration(_codec).migrateIfNeeded(dir);
      _migrated = true;
    }
    return dir;
  }
  // ...
}
```

### 5.4 数据流（迁移后）

```
[用户在前端编辑 Block]
      ↓
NoteFactory.saveNote(block)
      ↓
NoteRepository.saveNote(block)
      ↓
BlockCodec.encode(block)  →  Map<String, dynamic>
      ↓
TomlCodec.encode(Map)     →  TOML 字符串
      ↓
writeString  →  {docs}/notes/{id}.toml

[用户打开笔记]
      ↓
NoteRepository.readNote(id)
      ↓
readString  ←  {docs}/notes/{id}.toml
      ↓
TomlCodec.decode(String)  →  Map
      ↓
BlockCodec.decode(Map)    →  Block 树
```

## 6. TOML 表达约定

### 6.1 文件结构

每个块是一个 `[[blocks]]` 表，字段：

| Block 字段 | TOML key | 类型 | 备注 |
|---|---|---|---|
| `id` | `id` | string | 必填 |
| `type` (tag) | `type` | string | 必填 |
| `content` | `content` | string | 多行用 `"""` |
| `type.toJson()` | `data` | table | 类型专属字段 |
| `properties` | `properties` | table | 自由扩展 |
| `children` | `children` | array of tables | 递归 |
| `createdAt` | `created_at` | int (ms) | |
| `updatedAt` | `updated_at` | int (ms) | |

### 6.2 示例（与后端 `test_article.toml` 对齐）

```toml
[[blocks]]
id = "note-root"
type = "page"
created_at = 1700000000000
updated_at = 1700003600000

[[blocks]]
id = "blk-h1"
type = "heading"
data = { level = 1 }
content = "AI 的未来"

[[blocks]]
id = "blk-code"
type = "code"
data = { language = "python" }
content = """
def hello():
    print("hi")
"""
```

### 6.3 命名风格

- **全部 snake_case**：`created_at` / `updated_at` / `source_block_id` / `ref_block_id` / `block_id`
- **`BlockCodec` 的 Map 输出本来就是 snake_case**（已核对 `block_codec.dart`：`'created_at'` / `'updated_at'`，以及 `EmbedCardType.toJson()` 的 `'source_block_id'`、`MentionFormat` 的 `'block_id'`）——**命名已统一，无需调整**，直接交给 TOML 编码器即可。

## 7. 错误处理

| 场景 | 行为 |
|---|---|
| 迁移时某 `.json` 解析失败 | 保留该 `.json`，日志告警，继续迁移其他 |
| 迁移时写 `.toml` 失败 | 不删 `.json`，日志告警 |
| 读 `.toml` 解析失败 | `readNote` 返回 `null`（与现行为一致） |
| `listAllNotes` 遇坏文件 | 降级为用文件名当 title（`note_repository.dart:90-99` 现有行为，保留） |
| 进程崩溃中断迁移 | 下次启动重试（幂等：成功才删 `.json`） |

## 8. 测试策略

项目当前无 `test/` 目录。**本次新增最小测试**（验证不回归）：

```
test/core/note/persistence/
├── toml_codec_test.dart       # Map ↔ TOML roundtrip
├── note_repository_test.dart  # save→read roundtrip（用临时目录）
└── note_migration_test.dart   # 给一个 .json，迁移后变 .toml，内容等价
```

**测试用例（最小集）**：
1. `TomlCodec`：含 children 嵌套 + RichText spans 的 Map，roundtrip 后等价
2. `NoteRepository`：save 一个含 3 种块的笔记 → read 回来 → Block 树等价
3. `NoteMigration`：造一个老 `.json`（用旧 `BlockCodec` 输出）→ migrate → 生成 `.toml` + 删 `.json` → 读 `.toml` 等价于原 Block

## 9. 实施步骤（建议顺序）

1. `pubspec.yaml` 加 `toml` 依赖（实施时 `flutter pub add toml` 取最新稳定版），`flutter pub get`
2. 新建 `persistence/toml_codec.dart` + 单测
3. 新建 `persistence/note_migration.dart` + 单测
4. 改 `persistence/note_repository.dart`（6 处 + 构造函数加迁移钩子）+ 单测
5. 改 `persistence/persistence.dart` barrel（export 新类）
6. 手动验证：跑 `block_editor_demo`，创建笔记 → 检查 `{docs}/notes/*.toml` 文件内容
7. 迁移验证：手动放一个老 `.json` → 启动 → 确认变 `.toml`

## 10. 风险与缓解

| 风险 | 缓解 |
|---|---|
| `toml` 包对嵌套 array-of-tables 的 encode 支持不完整 | 步骤 2 单测先验证最复杂结构（嵌套 children）；不行则回退手写 codec |
| TOML 不支持 `null` 值 | `content`/`caption` 等可空字段用 `omitempty`（Map 层就不放 key）；已在 `BlockCodec` 的 Map 里处理 |
| 多行 `content` 里含 `"""` | `toml` 包自动转义；单测覆盖代码块场景 |
| 迁移期间用户操作 | 迁移在 `_getNotesDir` 内同步完成（毫秒级），且只跑一次；不在并发写时触发 |
| `toml` 包体积 | pub.dev `toml` 纯 Dart ~30KB，可接受 |

## 11. 不在本 spec 范围（YAGNI）

- ❌ 块 ID diff（设计文档 3.2 节明确"行号版够用"）
- ❌ `ValidateDocument` 校验工具
- ❌ Prompt 重构（后端，不动）
- ❌ JSON↔TOML 命名风格统一（已知项，不本次修）
- ❌ `storage_analyze_demo` 加"删笔记"功能（可后续单独做）

## 12. 验收标准

- [ ] `flutter pub get` 成功，无依赖冲突
- [ ] `flutter analyze lib/core/note` 0 error
- [ ] 3 个新增单测全绿
- [ ] `block_editor_demo` 能创建/读取/编辑笔记，文件落盘为 `.toml`
- [ ] 老 `.json` 笔记启动后自动变 `.toml`，内容等价
- [ ] `dev_ctr_hello` 后端**未被修改**（git diff 验证）
