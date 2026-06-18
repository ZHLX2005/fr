# Note 持久化层 JSON→TOML 迁移 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `lib/core/note` 的笔记文件存储格式从 JSON 改为 TOML，并自动迁移老 `.json` 笔记。

**Architecture:** `BlockCodec`（领域层，产出 `Map<String,dynamic>`）保持不变。新增 `TomlCodec` 做 `Map ↔ TOML 字符串`（薄包装 `toml` 包）。新增 `NoteMigration` 做 `.json → .toml` 一次性迁移（app 内懒触发、幂等、失败保留原文件）。`NoteRepository` 改 6 处 IO 调用 + 注入迁移钩子，并把目录获取抽成可注入参数以便测试。上层 `NoteFactory` 公开 API 不变，9 个调用方 0 改动。

**Tech Stack:** Flutter/Dart（sdk ^3.11.1）、`toml` 包（pub.dev，TOML 1.0）、`flutter test`、Conventional Commits。

---

## ⚠️ 计划启动前的关键说明（spec 的如实修正）

Spec §6.2 的示例把 `content` 写成扁平字符串（`content = "AI 的未来"`）。**这是简化，与实际不符**。

核对 `core/block_codec.dart:17`：`'content': block.content.toJson()`——`content` 是 `RichText.toJson()` 返回的 **Map**（`{spans: [...]}`），不是 string。

因此**实际落盘的 TOML** `content` 是一个 table：

```toml
[[blocks]]
id = "blk-h1"
type = "heading"
data = { level = 1 }
content = { spans = [{ text = "AI 的未来" }] }
created_at = 1700000000000
updated_at = 1700003600000
```

这是**忠实于领域模型**的格式——保证 `save → load` 无损 roundtrip，`TomlCodec` 维持单一职责（纯 `Map ↔ String`，不懂 Block 语义）。

> **与本计划无关（YAGNI，不实现）**：后端 `dev_ctr_hello/lib/ai/cmd/article/test_article.toml` 用的是"扁平 `content = "..."`"格式（给 AI 读的简化版）。**前端持久化的 TOML ≠ 后端 AI 操作的 TOML**。若未来要"前端 TOML 直传后端"，需另做一个"扁平化适配器"——那是独立工作，不在本计划范围。

**文件结构总览：**

```
lib/core/note/persistence/
├── persistence.dart           # barrel，新增 export（Task 5）
├── note_repository.dart       # 改 6 处 + 可注入目录（Task 4）
├── toml_codec.dart            # 新增：Map ↔ TOML（Task 2）
└── note_migration.dart        # 新增：.json → .toml 迁移（Task 3）

test/core/note/persistence/    # 新增测试目录
├── toml_codec_test.dart       # Task 2
├── note_migration_test.dart   # Task 3
└── note_repository_test.dart  # Task 4

pubspec.yaml                   # 加 toml 依赖（Task 1）
```

---

## Task 1: 添加 `toml` 依赖

**Files:**
- Modify: `pubspec.yaml`（在 `dependencies:` 块内）

- [ ] **Step 1: 用 flutter pub add 添加依赖（自动取最新稳定版并写入 pubspec）**

Run: `flutter pub add toml`
Expected: 输出含 `Resolving dependencies...` 和 `+ toml <version>`，无错误。

- [ ] **Step 2: 验证 pubspec.yaml 已写入**

Run: `flutter pub deps --no-dev | grep toml` 或直接检查 `pubspec.yaml` 出现 `toml:` 行。
Expected: 看到类似 `toml ^0.x.x` 的条目。

- [ ] **Step 3: 验证包可 import**

Run: `dart -e "import 'package:toml/toml.dart'; void main(){}"`
Expected: 无输出（import 成功）。若报错 `target of URI doesn't exist`，回 Step 1 重试 `flutter pub get`。

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore(note): add toml dependency for TOML persistence"
```

---

## Task 2: `TomlCodec`（TDD）

单一职责：`Map<String, dynamic> ↔ TOML 字符串`。纯薄包装 `toml` 包。

**Files:**
- Create: `lib/core/note/persistence/toml_codec.dart`
- Test: `test/core/note/persistence/toml_codec_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `test/core/note/persistence/toml_codec_test.dart`：

```dart
import 'package:test/test.dart';
import 'package:xiaodouzi_fr/core/note/persistence/toml_codec.dart';

/// 真实 BlockCodec 输出的 Map 形状（content 是 spans table，data 是 table，
/// children 是 array of maps）—— 用这个验证 TOML 能无损 roundtrip。
Map<String, dynamic> _sampleBlockMap() => {
      'id': 'blk-1',
      'type': 'heading',
      'data': {'level': 2},
      'content': {
        'spans': [
          {'text': '标题'},
          {'text': '加粗', 'format': {'type': 'bold'}},
        ],
      },
      'children': [
        {
          'id': 'blk-1-1',
          'type': 'paragraph',
          'data': {},
          'content': {'spans': [{'text': '子段落'}]},
          'children': <Map<String, dynamic>>[],
          'properties': <String, dynamic>{},
          'created_at': 1700000000000,
          'updated_at': 1700003600000,
        },
      ],
      'properties': <String, dynamic>{'tag': 'draft'},
      'created_at': 1700000000000,
      'updated_at': 1700003600000,
    };

void main() {
  late TomlCodec codec;

  setUp(() {
    codec = TomlCodec();
  });

  test('encode then decode returns an equivalent Map (deep roundtrip)', () {
    final original = _sampleBlockMap();
    final tomlString = codec.encode(original);
    final decoded = codec.decode(tomlString);

    expect(decoded['id'], 'blk-1');
    expect(decoded['type'], 'heading');
    expect(decoded['data'], {'level': 2});
    // content 是 spans table，roundtrip 后仍含 spans 数组
    final content = decoded['content'] as Map;
    expect(content.containsKey('spans'), isTrue);
    final spans = content['spans'] as List;
    expect(spans.length, 2);
    expect((spans[0] as Map)['text'], '标题');
    final children = decoded['children'] as List;
    expect(children.length, 1);
    expect((children[0] as Map)['type'], 'paragraph');
    expect(decoded['properties'], {'tag': 'draft'});
    expect(decoded['created_at'], 1700000000000);
  });

  test('encode handles empty data table and empty children', () {
    final map = {
      'id': 'p',
      'type': 'paragraph',
      'data': <String, dynamic>{},
      'content': {'spans': <Map<String, dynamic>>[]},
      'children': <Map<String, dynamic>>[],
      'properties': <String, dynamic>{},
      'created_at': 1,
      'updated_at': 2,
    };
    final decoded = codec.decode(codec.encode(map));
    expect(decoded['type'], 'paragraph');
    expect((decoded['content'] as Map)['spans'] as List, isEmpty);
  });

  test('decode of a hand-written TOML string parses correctly', () {
    const toml = '''
id = "x"
type = "paragraph"
data = {}
content = { spans = [{ text = "hi" }] }
children = []
properties = {}
created_at = 10
updated_at = 20
''';
    final decoded = codec.decode(toml);
    expect(decoded['id'], 'x');
    expect(decoded['type'], 'paragraph');
    expect(
      ((decoded['content'] as Map)['spans'] as List)[0],
      {'text': 'hi'},
    );
  });

  test('encode output contains a [[blocks]]-like table for array-of-maps', () {
    final doc = {
      'blocks': [_sampleBlockMap()],
    };
    final out = codec.encode(doc);
    expect(out, contains('[[blocks]]'));
    expect(out, contains('id = "blk-1"'));
  });
}
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `flutter test test/core/note/persistence/toml_codec_test.dart`
Expected: FAIL，错误类似 `Target of URI doesn't exist 'package:.../toml_codec.dart'` 或 `TomlCodec isn't defined`。

- [ ] **Step 3: 实现 `TomlCodec`**

创建 `lib/core/note/persistence/toml_codec.dart`：

```dart
import 'package:toml/toml.dart';

/// `Map<String, dynamic>` ↔ TOML 字符串 的薄包装编解码器。
///
/// 仅在 [NoteRepository] 的 IO 边界使用，领域层（Block / BlockCodec）
/// 不感知存在 TOML 这种格式。对任意嵌套 Map 做无损 roundtrip。
class TomlCodec {
  /// Map → TOML 字符串。
  ///
  /// 输入应是 [BlockCodec.encode] 的产物：含嵌套 children 数组、
  /// content/data/properties table、snake_case 顶层键。
  String encode(Map<String, dynamic> map) {
    return TomlDocument.fromMap(map).toString();
  }

  /// TOML 字符串 → Map。
  ///
  /// 解析失败时抛 [TomlException]（由调用方决定降级策略）。
  Map<String, dynamic> decode(String toml) {
    return TomlDocument.parse(toml).toMap();
  }
}
```

> **注意**：`TomlCodec` 与 `NoteRepository`/`NoteMigration` 同属 `persistence` 包，但本文件不 import 它们——保持单向依赖（`repository → codec`，不反向）。

- [ ] **Step 4: 跑测试，确认通过**

Run: `flutter test test/core/note/persistence/toml_codec_test.dart`
Expected: `All 4 tests passed!`

> **若失败**：
> - 若 `TomlDocument.fromMap` 不存在或签名不同：查 `toml` 包 API（`dart doc` 或 pub.dev README），调整为等价的"Map → Document → String"路径，常见替代是 `Toml.encode(map)` / `Toml.decode(string)`（顶层函数形式）。保持 `encode/decode` 方法签名不变，只换内部实现。
> - 若 roundtrip 后类型不符（如 int 变 float）：在测试断言里放宽或用 `equals` 配合类型转换；记录到 commit message。

- [ ] **Step 5: Commit**

```bash
git add lib/core/note/persistence/toml_codec.dart test/core/note/persistence/toml_codec_test.dart
git commit -m "feat(note/persistence): add TomlCodec for Map<->TOML conversion"
```

---

## Task 3: `NoteMigration`（TDD）

单一职责：扫描 `notes/` 下 `*.json`，逐个转写为 `*.toml`，成功才删原文件，失败保留+日志。幂等。

**Files:**
- Create: `lib/core/note/persistence/note_migration.dart`
- Test: `test/core/note/persistence/note_migration_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `test/core/note/persistence/note_migration_test.dart`：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xiaodouzi_fr/core/note/persistence/note_migration.dart';
import 'package:xiaodouzi_fr/core/note/persistence/toml_codec.dart';
import 'package:xiaodouzi_fr/core/note/core/core.dart';

void main() {
  late Directory tempDir;
  late BlockCodec codec;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('note_migration_test_');
    codec = _buildCodec();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('migrates a .json note to .toml and deletes the .json', () async {
    // 1. 构造一个老 JSON 笔记（用 BlockCodec.encode + jsonEncode，模拟旧格式）
    final block = Block(
      id: 'old-note-1',
      type: const ParagraphType(),
      content: RichText.text('老笔记内容'),
    );
    final jsonMap = codec.encode(block);
    final jsonFile = File(p.join(tempDir.path, 'old-note-1.json'));
    await jsonFile.writeAsString(jsonEncode(jsonMap));

    // 2. 迁移
    final migration = NoteMigration(codec, TomlCodec());
    final count = await migration.migrateIfNeeded(tempDir);

    // 3. .json 应已删除，.toml 应存在
    expect(count, 1);
    expect(await jsonFile.exists(), isFalse);
    final tomlFile = File(p.join(tempDir.path, 'old-note-1.toml'));
    expect(await tomlFile.exists(), isTrue);

    // 4. .toml 读回应等价于原 Block（比 toPlainText）
    final tomlMap = TomlCodec().decode(await tomlFile.readAsString());
    final restored = codec.decode(tomlMap);
    expect(restored.content.toPlainText(), '老笔记内容');
    expect(restored.type, isA<ParagraphType>());
  });

  test('is idempotent: running twice does nothing the second time', () async {
    final block = Block(
      id: 'old-note-2',
      type: const ParagraphType(),
      content: RichText.text('内容'),
    );
    final jsonFile = File(p.join(tempDir.path, 'old-note-2.json'));
    await jsonFile.writeAsString(jsonEncode(codec.encode(block)));

    final migration = NoteMigration(codec, TomlCodec());
    await migration.migrateIfNeeded(tempDir);
    final secondCount = await migration.migrateIfNeeded(tempDir);

    expect(secondCount, 0);
  });

  test('skips a corrupted .json without deleting it', () async {
    final badJson = File(p.join(tempDir.path, 'broken.json'));
    await badJson.writeAsString('{ this is not valid json');

    final migration = NoteMigration(codec, TomlCodec());
    final count = await migration.migrateIfNeeded(tempDir);

    expect(count, 0); // 没成功迁移任何
    expect(await badJson.exists(), isTrue); // 坏文件保留
  });

  test('does nothing when directory has only .toml files', () async {
    final tomlFile = File(p.join(tempDir.path, 'new.toml'));
    await tomlFile.writeAsString('id = "new"\ntype = "paragraph"\n');

    final migration = NoteMigration(codec, TomlCodec());
    final count = await migration.migrateIfNeeded(tempDir);

    expect(count, 0);
  });
}

/// 构造一个真实可用的 BlockCodec（与 NoteFactory.create 一致）。
BlockCodec _buildCodec() {
  final typeRegistry = BlockTypeRegistry(BlockTypeRegistrar().createFactories());
  final formatRegistry =
      InlineFormatRegistry(InlineFormatRegistrar().createFactories());
  final richTextCodec = RichTextCodec(formatRegistry);
  return BlockCodec(typeRegistry, richTextCodec);
}
```

> 依赖 `package:path`（transitively 已可用，`flutter pub deps` 可见）。若测试报 `path` 不可 import，加 `path: ^1.9.0` 到 `dev_dependencies`。

- [ ] **Step 2: 跑测试，确认失败**

Run: `flutter test test/core/note/persistence/note_migration_test.dart`
Expected: FAIL，`NoteMigration isn't defined`。

- [ ] **Step 3: 实现 `NoteMigration`**

创建 `lib/core/note/persistence/note_migration.dart`：

```dart
import 'dart:convert';
import 'dart:io';

import '../core/block_codec.dart';
import 'toml_codec.dart';

/// 一次性迁移：把 `notes/` 下的老 `*.json` 笔记转写为 `*.toml`。
///
/// 设计要点：
/// - **幂等**：只有写 `.toml` 成功后才删 `.json`；中断后下次重试安全。
/// - **容错**：单个文件解析失败不中断整体，保留坏 `.json` + 打印日志。
/// - **无状态触发**：调用方负责"只跑一次"的守护（见 [NoteRepository]）。
class NoteMigration {
  final BlockCodec _codec;
  final TomlCodec _tomlCodec;

  NoteMigration(this._codec, this._tomlCodec);

  /// 扫描 [notesDir] 下的 `*.json`，逐个迁移为同名 `.toml`。
  ///
  /// 返回成功迁移的文件数（0 = 无需迁移）。
  Future<int> migrateIfNeeded(Directory notesDir) async {
    if (!await notesDir.exists()) return 0;

    int migrated = 0;
    final jsonFiles = notesDir
        .listSync(followLinks: false)
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'));

    for (final jsonFile in jsonFiles) {
      final ok = await _migrateOne(jsonFile);
      if (ok) migrated++;
    }
    return migrated;
  }

  /// 迁移单个文件。成功 = 写了 `.toml` 且删了 `.json`。
  Future<bool> _migrateOne(File jsonFile) async {
    final tomlPath = '${jsonFile.path.substring(0, jsonFile.path.length - 5)}.toml';
    final tomlFile = File(tomlPath);

    try {
      final raw = await jsonFile.readAsString();
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final tomlString = _tomlCodec.encode(map);
      await tomlFile.writeAsString(tomlString);
      await jsonFile.delete();
      return true;
    } catch (e) {
      // 保留坏文件，仅日志，不抛——下次启动可重试或人工介入。
      // ignore: avoid_print
      print('[NoteMigration] skip ${jsonFile.path}: $e');
      return false;
    }
  }
}
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `flutter test test/core/note/persistence/note_migration_test.dart`
Expected: `All 4 tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/core/note/persistence/note_migration.dart test/core/note/persistence/note_migration_test.dart
git commit -m "feat(note/persistence): add NoteMigration for json->toml one-shot migration"
```

---

## Task 4: 改造 `NoteRepository`（TDD）

改 6 处 IO 调用（JSON→TOML），加可注入目录参数（测试用），加懒触发迁移钩子。

**Files:**
- Modify: `lib/core/note/persistence/note_repository.dart`
- Test: `test/core/note/persistence/note_repository_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `test/core/note/persistence/note_repository_test.dart`：

```dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xiaodouzi_fr/core/note/persistence/note_repository.dart';
import 'package:xiaodouzi_fr/core/note/persistence/toml_codec.dart';
import 'package:xiaodouzi_fr/core/note/core/core.dart';

void main() {
  late Directory tempDir;
  late BlockCodec codec;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('note_repo_test_');
    codec = _buildCodec();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  NoteRepository _newRepo() => NoteRepository(
        codec,
        tomlCodec: TomlCodec(),
        notesDirProvider: () async => tempDir,
      );

  test('save then read roundtrips a block tree as .toml', () async {
    final repo = _newRepo();
    final block = Block(
      id: 'r1',
      type: const ParagraphType(),
      content: RichText.text('hello toml'),
    );

    await repo.saveNote(block);

    // 落盘为 .toml
    final tomlFile = File(p.join(tempDir.path, 'r1.toml'));
    expect(await tomlFile.exists(), isTrue);
    final jsonFile = File(p.join(tempDir.path, 'r1.json'));
    expect(await jsonFile.exists(), isFalse);

    final loaded = await repo.readNote('r1');
    expect(loaded, isNotNull);
    expect(loaded!.content.toPlainText(), 'hello toml');
    expect(loaded.type, isA<ParagraphType>());
  });

  test('listAllNotes sees .toml files and returns NoteInfo', () async {
    final repo = _newRepo();
    await repo.saveNote(Block(
      id: 'r2',
      type: const ParagraphType(),
      content: RichText.text('first'),
    ));
    await repo.saveNote(Block(
      id: 'r3',
      type: const ParagraphType(),
      content: RichText.text('second'),
    ));

    final notes = await repo.listAllNotes();
    expect(notes.length, 2);
    expect(notes.map((n) => n.id).toSet(), {'r2', 'r3'});
  });

  test('deleteNote removes the .toml file', () async {
    final repo = _newRepo();
    await repo.saveNote(Block(
      id: 'r4',
      type: const ParagraphType(),
      content: RichText.text('gone'),
    ));
    await repo.deleteNote('r4');
    expect(await File(p.join(tempDir.path, 'r4.toml')).exists(), isFalse);
  });

  test('migrates legacy .json into .toml on first directory access', () async {
    // 1. 直接放一个老 .json（不经 repo，模拟历史遗留）
    final legacy = codec.encode(Block(
      id: 'legacy-1',
      type: const ParagraphType(),
      content: RichText.text('legacy content'),
    ));
    // 复刻旧 JSON 序列化
    final jsonStr = '{"id":"legacy-1","type":"paragraph",'
        '"content":{"spans":[{"text":"legacy content"}]},'
        '"children":[],"data":{},"properties":{},'
        '"created_at":1,"updated_at":2}';
    await File(p.join(tempDir.path, 'legacy-1.json'))
        .writeAsString(jsonStr);

    // 2. 首次访问触发迁移
    final repo = _newRepo();
    final notes = await repo.listAllNotes();

    // 3. .toml 出现，.json 消失，能读到内容
    expect(notes.any((n) => n.id == 'legacy-1'), isTrue);
    expect(await File(p.join(tempDir.path, 'legacy-1.json')).exists(), isFalse);
    final loaded = await repo.readNote('legacy-1');
    expect(loaded!.content.toPlainText(), 'legacy content');
  });
}

BlockCodec _buildCodec() {
  final typeRegistry = BlockTypeRegistry(BlockTypeRegistrar().createFactories());
  final formatRegistry =
      InlineFormatRegistry(InlineFormatRegistrar().createFactories());
  final richTextCodec = RichTextCodec(formatRegistry);
  return BlockCodec(typeRegistry, richTextCodec);
}
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `flutter test test/core/note/persistence/note_repository_test.dart`
Expected: FAIL——`NoteRepository` 构造函数还不接受 `tomlCodec` / `notesDirProvider` 参数，编译错误。

- [ ] **Step 3: 改造 `NoteRepository`**

打开 `lib/core/note/persistence/note_repository.dart`，做以下改动。

**3a. 改 import（`:1`）**——把 `dart:convert` 换成 `toml_codec` + `note_migration` + `toml` 包（仅 `_extractTitle` 等若用 json 则不需要，实际只 IO 用）：

```dart
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/core.dart';
import 'note_migration.dart';
import 'toml_codec.dart';
```

（删掉 `import 'dart:convert';`——JSON 编解码全部下放到 `NoteMigration`，仓库本体不再用 `jsonEncode/jsonDecode`。）

**3b. 改类定义（`:41-44`）**——加可注入字段 + 迁移钩子：

```dart
/// 笔记文件仓库 — 扫描 notes/ 下的 .toml 笔记文件。
///
/// 首次访问目录时懒触发老 .json → .toml 迁移（幂等，进程内只跑一次）。
class NoteRepository {
  final BlockCodec _codec;
  final TomlCodec _tomlCodec;
  final Future<Directory> Function() _notesDirProvider;
  bool _migrated = false;

  /// [notesDirProvider] 可注入：生产用 [getApplicationDocumentsDirectory]，
  /// 测试用临时目录。默认走 path_provider。
  NoteRepository(
    this._codec, {
    TomlCodec? tomlCodec,
    Future<Directory> Function()? notesDirProvider,
  })  : _tomlCodec = tomlCodec ?? TomlCodec(),
        _notesDirProvider = notesDirProvider ?? _defaultNotesDir;
```

**3c. 改 `_getNotesDir`（`:49-52`）**——加迁移触发：

```dart
  Future<Directory> _getNotesDir() async {
    final dir = await _notesDirProvider();
    if (!_migrated) {
      await NoteMigration(_codec, _tomlCodec).migrateIfNeeded(dir);
      _migrated = true;
    }
    return dir;
  }

  static Future<Directory> _defaultNotesDir() async {
    final docDir = await getApplicationDocumentsDirectory();
    return Directory('${docDir.path}${Platform.pathSeparator}notes');
  }
```

**3d. 改 `listAllNotes` 里的读取（`:63` 和 `:76`）**——`.json` → `.toml`，`jsonDecode` → `_tomlCodec.decode`：

```dart
      for (final entity in entities) {
        if (entity is File && entity.path.endsWith('.toml')) {
          files.add(entity);
        }
      }
```

```dart
        final toml = await file.readAsString();
        final block = _codec.decode(_tomlCodec.decode(toml));
```

**3e. 改 `saveNote`（`:171-173`）**——`.json` → `.toml`，`jsonEncode` → `_tomlCodec.encode`：

```dart
    final file = File(
      '${dir.path}${Platform.pathSeparator}${block.id}.toml',
    );
    await file.writeAsString(_tomlCodec.encode(_codec.encode(block)));
```

**3f. 改 `deleteNote`（`:180`）**：

```dart
    final file = File(
      '${dir.path}${Platform.pathSeparator}$id.toml',
    );
```

**3g. 改 `readNote`（`:189-193`）**：

```dart
    final file = File(
      '${dir.path}${Platform.pathSeparator}$id.toml',
    );
    if (!await file.exists()) return null;
    try {
      final toml = await file.readAsString();
      return _codec.decode(_tomlCodec.decode(toml));
    } catch (_) {
      return null;
    }
```

> `:46-47` 的 `encodeBlock` 方法（`Map<String, dynamic> encodeBlock(Block block) => _codec.encode(block);`）**保持不变**——它只产出 Map，与文件格式无关，`NoteFactory.serializeBlock` 仍可用。

> `:124-162` 的 `_extractTitle` / `_findFirstHeading` / `_countBlocks` **全部不动**——它们消费的是 `Block` 对象，不碰文件。

- [ ] **Step 4: 改 `factory.dart` 的 `NoteRepository` 构造调用**

打开 `lib/core/note/factory.dart:41`：

```dart
      repository: NoteRepository(blockCodec),
```

这一行**不需要改**——`NoteRepository` 的新参数都有默认值，旧调用方式完全兼容。

- [ ] **Step 5: 跑测试，确认通过**

Run: `flutter test test/core/note/persistence/note_repository_test.dart`
Expected: `All 4 tests passed!`

- [ ] **Step 6: 跑全量 persistence 测试，确认无回归**

Run: `flutter test test/core/note/persistence/`
Expected: `All 12 tests passed!`（codec 4 + migration 4 + repository 4）

- [ ] **Step 7: 静态分析**

Run: `flutter analyze lib/core/note`
Expected: `No issues found!`（或仅有与本次无关的既有 warning）

- [ ] **Step 8: Commit**

```bash
git add lib/core/note/persistence/note_repository.dart lib/core/note/factory.dart test/core/note/persistence/note_repository_test.dart
git commit -m "refactor(note/persistence): switch note storage from JSON to TOML

- NoteRepository now reads/writes .toml via TomlCodec
- injectable notesDirProvider for testability
- lazy one-shot .json->.toml migration on first dir access
- BlockCodec and NoteFactory public API unchanged"
```

---

## Task 5: 更新 barrel export

**Files:**
- Modify: `lib/core/note/persistence/persistence.dart`

- [ ] **Step 1: 导出新类**

把 `lib/core/note/persistence/persistence.dart` 的内容改为：

```dart
export 'note_migration.dart';
export 'note_repository.dart';
export 'toml_codec.dart';
```

> 原文件只有 `export 'note_repository.dart';`。新增两条。`NoteMigration` 和 `TomlCodec` 作为 persistence 层公共类型导出，供 `factory.dart` 等未来按需使用。

- [ ] **Step 2: 静态分析确认无破坏**

Run: `flutter analyze lib/core/note`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/core/note/persistence/persistence.dart
git commit -m "chore(note/persistence): export TomlCodec and NoteMigration"
```

---

## Task 6: 手动验证（端到端）

**Files:** 无代码改动，仅运行验证。

- [ ] **Step 1: 启动 app，进 block_editor_demo，创建一篇笔记**

Run: `flutter run`（或 IDE 运行），进入 Lab → 块编辑器 demo，新建一篇含标题+段落+代码块的笔记。

- [ ] **Step 2: 确认落盘为 .toml**

查找应用 documents 目录（平台相关：Android `/data/data/.../files/notes/`、macOS `~/Library/.../notes/`），确认出现 `<id>.toml` 文件，**无** `.json`。

- [ ] **Step 3: 肉眼检查 .toml 内容合理**

打开该 `.toml`，确认：
- 每个块是 `[[blocks]]`（或顶层 `[[blocks]]` 数组）
- `content` 是 `{ spans = [...] }` table（非扁平字符串——见计划开头说明）
- 多行代码块内容用 `"""` 折叠
- snake_case 键名（`created_at` / `updated_at`）

- [ ] **Step 4: 重启 app，确认笔记能读回**

杀掉 app 重启，重新进入 demo，确认刚创建的笔记仍在且内容完整（文字、代码、结构）。

- [ ] **Step 5: 迁移验证（可选但有价值）**

若手头有老 `.json` 笔记：直接放到 `notes/` 目录（命名 `<id>.json`，内容为旧 `BlockCodec` JSON），启动 app 进入存储分析或块编辑器，确认：
- `.json` 消失
- 同名 `.toml` 出现
- 内容等价

- [ ] **Step 6: 确认 storage_analyze_demo 仍正常**

进入 Lab → 存储分析 demo，确认笔记列表能列出（`listAllNotes` 读 `.toml`）、点开能预览原始内容（`readRawNoteContent` 读 `.toml`）。

- [ ] **Step 7: 无需 commit**（纯验证步）

---

## Task 7: 最终验证 & 验收 checklist

**Files:** 无。

- [ ] **Step 1: 全量测试**

Run: `flutter test`
Expected: 全绿（含新增 12 个 persistence 测试 + 项目既有测试）。

- [ ] **Step 2: 全量静态分析**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: 确认后端未被修改**

Run: `cd D:/DevProjects/my/github/dev_ctr_hello && git status`
Expected: `nothing to commit, working tree clean`（或与本次无关的既有改动）。**lib/ai 不应有任何 diff。**

- [ ] **Step 4: 对照 spec §12 验收标准逐条勾选**

- [ ] `flutter pub get` 成功，无依赖冲突
- [ ] `flutter analyze lib/core/note` 0 error
- [ ] 3 个新增单测文件全绿（codec 4 + migration 4 + repository 4 = 12 用例）
- [ ] `block_editor_demo` 能创建/读取/编辑笔记，文件落盘为 `.toml`
- [ ] 老 `.json` 笔记启动后自动变 `.toml`，内容等价
- [ ] `dev_ctr_hello` 后端**未被修改**（git diff 验证）

- [ ] **Step 5: 无需 commit**（验收步）

---

## 完成准则

全部 7 个 Task 的所有 checkbox 勾选完毕，即交付完成。
