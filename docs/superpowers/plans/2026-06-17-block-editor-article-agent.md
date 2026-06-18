# block_editor_demo 接入 article/edit Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `block_editor_demo` 的 `sendAiPrompt` 从 mock 接到真实后端 `/api/v1/article/edit`，实现全文编辑 + diff 展示。

**Architecture:** `NoteRepository`/`NoteFactory` 加 Block↔TOML 字符串的便捷方法；新建 `ArticleEditService`（函数注入易测）封装 endpoint + 转换；`EditorState.sendAiPrompt` 改真实调用、`confirmAiResult` 改全文替换、加 `_aiDiff`/`_aiSettings`/`_aiError` 状态；`card.dart._buildAiResult` 接入 `DiffViewer`；`block_editor_demo` 通过 `ProviderScope.containerOf` 拿 `articleEndpointProvider` 注入 service，AppBar 加配置入口。

**Tech Stack:** Flutter/Dart（sdk ^3.11.1）、`flutter_test`、riverpod（`ProviderScope.containerOf`）、SharedPreferences、Conventional Commits。

---

## File Structure

```
lib/core/note/
├── persistence/note_repository.dart   # 加 encodeToml/decodeToml（Task 1）
└── factory.dart                       # 加 toTomlString/fromTomlString（Task 1）

lib/lab/demos/block_editor_demo/
├── ai/
│   ├── ai_settings_store.dart         # 新增：AiSettings + AiSettingsStore（Task 2）
│   ├── article_edit_service.dart      # 新增：service + 结果模型 + 异常（Task 3）
│   └── diff_viewer.dart               # 新增：diff 着色组件（Task 4）
├── state.dart                         # 改造：sendAiPrompt/confirmAiResult + 状态字段（Task 5）
├── card.dart                          # 改造：_buildAiResult 接入 DiffViewer（Task 6）
└── block_editor_demo.dart             # 改造：注入 service + AppBar 配置入口（Task 7）

test/
├── core/note/persistence/note_repository_test.dart  # 加用例（Task 1）
└── lab/demos/block_editor_demo/ai/
    ├── ai_settings_store_test.dart    # 新增（Task 2）
    └── article_edit_service_test.dart # 新增（Task 3）
```

**Convention（来自前一个 plan，沿用）**：测试用 `package:flutter_test/flutter_test.dart`（项目只声明 flutter_test）。

---

## Task 1: `NoteRepository.encodeToml/decodeToml` + `NoteFactory.toTomlString/fromTomlString`

**Files:**
- Modify: `lib/core/note/persistence/note_repository.dart`
- Modify: `lib/core/note/factory.dart`
- Test: `test/core/note/persistence/note_repository_test.dart`（加用例）

- [ ] **Step 1: 加失败测试** — 在 `test/core/note/persistence/note_repository_test.dart` 的 `main()` 内追加：

```dart
  test('encodeToml then decodeToml roundtrips a block tree', () async {
    final repo = NoteRepository(
      codec,
      tomlCodec: TomlCodec(),
      notesDirProvider: () async => tempDir,
    );
    final block = Block(
      id: 'toml-rt',
      type: const HeadingType(),
      content: RichText.text('标题'),
    );

    final toml = repo.encodeToml(block);
    expect(toml, contains('id = '));
    expect(toml, contains('type = "heading"'));

    final restored = repo.decodeToml(toml);
    expect(restored, isNotNull);
    expect(restored!.id, 'toml-rt');
    expect(restored.content.toPlainText(), '标题');
  });

  test('decodeToml returns null on invalid TOML', () {
    final repo = NoteRepository(codec, tomlCodec: TomlCodec());
    expect(repo.decodeToml('this is not = valid = toml {{{'), isNull);
  });
```

（文件顶部已有的 `_buildCodec` helper、`setUp`/`tearDown` 复用，不要重复定义。）

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/note/persistence/note_repository_test.dart`
Expected: FAIL — `encodeToml`/`decodeToml` 未定义。

- [ ] **Step 3: 实现 `NoteRepository` 方法**

在 `lib/core/note/persistence/note_repository.dart` 的 `encodeBlock` 方法（`Map<String, dynamic> encodeBlock(Block block) => _codec.encode(block);`）下方追加：

```dart
  /// Block → TOML 字符串（复用 [BlockCodec] + [TomlCodec]）。
  String encodeToml(Block block) => _tomlCodec.encode(_codec.encode(block));

  /// TOML 字符串 → Block。解析失败返回 null（不抛异常，由调用方降级）。
  Block? decodeToml(String toml) {
    try {
      return _codec.decode(_tomlCodec.decode(toml));
    } catch (_) {
      return null;
    }
  }
```

- [ ] **Step 4: 实现 `NoteFactory` 方法**

在 `lib/core/note/factory.dart` 的 `serializeBlock` 方法（`Map<String, dynamic> serializeBlock(Block block) => _repository.encodeBlock(block);`）下方追加：

```dart
  /// Block 树 → TOML 字符串。用于发给后端 article/edit。
  String toTomlString(Block root) => _repository.encodeToml(root);

  /// TOML 字符串 → Block 树。解析失败返回 null。
  Block? fromTomlString(String toml) => _repository.decodeToml(toml);
```

- [ ] **Step 5: 跑测试确认通过**

Run: `flutter test test/core/note/persistence/note_repository_test.dart`
Expected: 之前的用例 + 新增 2 用例全绿。

- [ ] **Step 6: 静态分析**

Run: `flutter analyze lib/core/note`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/core/note/persistence/note_repository.dart lib/core/note/factory.dart test/core/note/persistence/note_repository_test.dart
git commit -m "feat(note): add Block<->TOML string helpers on NoteRepository/NoteFactory" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `AiSettings` + `AiSettingsStore`

demo 独立的 apiKey/model/baseUrl 存储（SharedPreferences）。

**Files:**
- Create: `lib/lab/demos/block_editor_demo/ai/ai_settings_store.dart`
- Test: `test/lab/demos/block_editor_demo/ai/ai_settings_store_test.dart`

- [ ] **Step 1: 写失败测试** — 创建 `test/lab/demos/block_editor_demo/ai/ai_settings_store_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/lab/demos/block_editor_demo/ai/ai_settings_store.dart';

void main() {
  // 每个测试用独立的 SharedPreferences 实例（用不同 prefix 隔离）
  AiSettingsStore storeWith(String prefix) => AiSettingsStore(prefsKey: 'test_$prefix');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('load returns empty defaults when nothing saved', () async {
    final store = storeWith('empty');
    final s = await store.load();
    expect(s.apiKey, '');
    expect(s.model, '');
    expect(s.baseUrl, '');
    expect(s.isConfigured, isFalse);
  });

  test('save then load roundtrips all fields', () async {
    final store = storeWith('roundtrip');
    await store.save(const AiSettings(
      apiKey: 'sk-xxx',
      model: 'glm-4.7',
      baseUrl: 'https://example.com',
    ));
    final loaded = await store.load();
    expect(loaded.apiKey, 'sk-xxx');
    expect(loaded.model, 'glm-4.7');
    expect(loaded.baseUrl, 'https://example.com');
    expect(loaded.isConfigured, isTrue);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/lab/demos/block_editor_demo/ai/ai_settings_store_test.dart`
Expected: FAIL — `AiSettingsStore`/`AiSettings` 未定义。

- [ ] **Step 3: 实现** — 创建 `lib/lab/demos/block_editor_demo/ai/ai_settings_store.dart`：

```dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// block_editor_demo 的 AI 配置（独立于 ai_chat_provider）。
class AiSettings {
  final String apiKey;
  final String model;
  final String baseUrl;

  const AiSettings({
    this.apiKey = '',
    this.model = '',
    this.baseUrl = '',
  });

  bool get isConfigured => apiKey.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'apiKey': apiKey,
        'model': model,
        'baseUrl': baseUrl,
      };

  factory AiSettings.fromJson(Map<String, dynamic> json) => AiSettings(
        apiKey: json['apiKey'] as String? ?? '',
        model: json['model'] as String? ?? '',
        baseUrl: json['baseUrl'] as String? ?? '',
      );
}

/// 用 SharedPreferences 持久化 [AiSettings]。
///
/// [prefsKey] 可注入，便于测试用独立 key 隔离。
class AiSettingsStore {
  final String prefsKey;
  AiSettingsStore({this.prefsKey = 'block_editor_ai_settings'});

  Future<AiSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) return const AiSettings();
    try {
      return AiSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AiSettings();
    }
  }

  Future<void> save(AiSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, jsonEncode(settings.toJson()));
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/lab/demos/block_editor_demo/ai/ai_settings_store_test.dart`
Expected: `All 2 tests passed!`

- [ ] **Step 5: 静态分析**

Run: `flutter analyze lib/lab/demos/block_editor_demo/ai/ai_settings_store.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/lab/demos/block_editor_demo/ai/ai_settings_store.dart test/lab/demos/block_editor_demo/ai/ai_settings_store_test.dart
git commit -m "feat(block-editor): add demo-local AiSettings + SharedPreferences store" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: `ArticleEditService`

封装 Block→TOML→endpoint→TOML→Block。**用函数注入**（tear-off `endpoint.edit`）便于测试，免 mock http。

**Files:**
- Create: `lib/lab/demos/block_editor_demo/ai/article_edit_service.dart`
- Test: `test/lab/demos/block_editor_demo/ai/article_edit_service_test.dart`

- [ ] **Step 1: 写失败测试** — 创建 `test/lab/demos/block_editor_demo/ai/article_edit_service_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/api/api_response.dart';
import 'package:xiaodouzi_fr/api/goframe/article/article_endpoint.dart';
import 'package:xiaodouzi_fr/core/note/core/core.dart';
import 'package:xiaodouzi_fr/lab/demos/block_editor_demo/ai/ai_settings_store.dart';
import 'package:xiaodouzi_fr/lab/demos/block_editor_demo/ai/article_edit_service.dart';

BlockCodec _codec() {
  final typeRegistry = BlockTypeRegistry(BlockTypeRegistrar().createFactories());
  final formatRegistry =
      InlineFormatRegistry(InlineFormatRegistrar().createFactories());
  return BlockCodec(typeRegistry, RichTextCodec(formatRegistry));
}

// 构造一个"已应用编辑"的 ArticleEditResponse（modifiedToml 是合法 TOML，能被 NoteFactory.fromTomlString 解析）
ArticleEditResponse _editResponse({required bool hasEdit}) {
  if (!hasEdit) {
    return const ArticleEditResponse(
      diff: '',
      conclusion: '这篇文章讲 AI。',
      modifiedToml: '',
      hasEdit: false,
    );
  }
  // hasEdit=true：modifiedToml 必须是合法 TOML，对应一个含 heading 的 block
  const toml = '''id = "root"
type = "page"
content = { spans = [{ text = "" }] }
children = []
data = {}
properties = {}
created_at = 1
updated_at = 2
''';
  return const ArticleEditResponse(
    diff: '@@ -1,1 +1,1 @@\n-old\n+new',
    conclusion: '修改完成',
    modifiedToml: toml,
    hasEdit: true,
  );
}

void main() {
  late NoteFactory noteFactory;

  setUp(() {
    // 用真实的 NoteFactory.create()（它内部组装 codec + repository）
    noteFactory = NoteFactory.create();
  });

  test('edit returns hasEdit=true with parsed modifiedBlock', () async {
    final service = ArticleEditService(
      editCall: ({required apiKey, required articleToml, required prompt, model, baseUrl}) async =>
          ApiResponse(code: 0, message: '', data: _editResponse(hasEdit: true)),
      noteFactory: noteFactory,
    );
    final root = Block(id: 'root', type: const PageType());

    final result = await service.edit(
      rootNote: root,
      prompt: '改一下',
      settings: const AiSettings(apiKey: 'sk-x'),
    );

    expect(result.hasEdit, isTrue);
    expect(result.diff, contains('-old'));
    expect(result.modifiedBlock, isNotNull);
  });

  test('edit returns hasEdit=false with conclusion, no modifiedBlock', () async {
    final service = ArticleEditService(
      editCall: ({required apiKey, required articleToml, required prompt, model, baseUrl}) async =>
          ApiResponse(code: 0, message: '', data: _editResponse(hasEdit: false)),
      noteFactory: noteFactory,
    );

    final result = await service.edit(
      rootNote: Block(id: 'r', type: const PageType()),
      prompt: '主题是什么',
      settings: const AiSettings(apiKey: 'sk-x'),
    );

    expect(result.hasEdit, isFalse);
    expect(result.conclusion, '这篇文章讲 AI。');
    expect(result.modifiedBlock, isNull);
  });

  test('edit throws on non-success response', () async {
    final service = ArticleEditService(
      editCall: ({required apiKey, required articleToml, required prompt, model, baseUrl}) async =>
          ApiResponse<ArticleEditResponse>(code: 500, message: 'server boom', data: null),
      noteFactory: noteFactory,
    );

    expect(
      () => service.edit(
        rootNote: Block(id: 'r', type: const PageType()),
        prompt: 'x',
        settings: const AiSettings(apiKey: 'sk-x'),
      ),
      throwsA(isA<ArticleEditException>()),
    );
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/lab/demos/block_editor_demo/ai/article_edit_service_test.dart`
Expected: FAIL — `ArticleEditService`/`ArticleEditResult`/`ArticleEditException` 未定义。

- [ ] **Step 3: 实现** — 创建 `lib/lab/demos/block_editor_demo/ai/article_edit_service.dart`：

```dart
import '../../../api/api_response.dart';
import '../../../api/goframe/article/article_endpoint.dart';
import '../../../core/note/core/core.dart';
import 'ai_settings_store.dart';

/// 调用后端 article/edit 的函数签名（= ArticleEndpoint.edit 的 tear-off 类型）。
typedef ArticleEditCall =
    Future<ApiResponse<ArticleEditResponse>> Function({
  required String apiKey,
  required String articleToml,
  required String prompt,
  String? model,
  String? baseUrl,
});

/// article/edit 的结果（已做 Block 转换）。
class ArticleEditResult {
  final bool hasEdit;
  final String conclusion;
  final String diff;
  final Block? modifiedBlock; // hasEdit=true 时有效

  const ArticleEditResult({
    required this.hasEdit,
    required this.conclusion,
    required this.diff,
    this.modifiedBlock,
  });
}

class ArticleEditException implements Exception {
  final String message;
  ArticleEditException(this.message);
  @override
  String toString() => 'ArticleEditException: $message';
}

/// 封装 Block → TOML → endpoint → TOML → Block 的完整链路。
///
/// [editCall] 注入 [ArticleEndpoint.edit] 的 tear-off，便于测试替换为假函数。
class ArticleEditService {
  final ArticleEditCall _editCall;
  final NoteFactory _noteFactory;

  ArticleEditService({required ArticleEditCall editCall, required NoteFactory noteFactory})
      : _editCall = editCall,
        _noteFactory = noteFactory;

  /// 工厂构造：绑定真实的 [ArticleEndpoint]。
  factory ArticleEditService.forEndpoint(ArticleEndpoint endpoint, NoteFactory noteFactory) {
    return ArticleEditService(editCall: endpoint.edit, noteFactory: noteFactory);
  }

  Future<ArticleEditResult> edit({
    required Block rootNote,
    required String prompt,
    required AiSettings settings,
  }) async {
    final toml = _noteFactory.toTomlString(rootNote);
    final resp = await _editCall(
      apiKey: settings.apiKey,
      articleToml: toml,
      prompt: prompt,
      model: settings.model.isEmpty ? null : settings.model,
      baseUrl: settings.baseUrl.isEmpty ? null : settings.baseUrl,
    );

    if (!resp.isSuccess || resp.data == null) {
      throw ArticleEditException(resp.message.isEmpty ? '请求失败' : resp.message);
    }
    final d = resp.data!;

    Block? modified;
    if (d.hasEdit) {
      modified = _noteFactory.fromTomlString(d.modifiedToml);
      if (modified == null) {
        throw ArticleEditException('修改后的 TOML 解析失败');
      }
    }

    return ArticleEditResult(
      hasEdit: d.hasEdit,
      conclusion: d.conclusion,
      diff: d.diff,
      modifiedBlock: modified,
    );
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/lab/demos/block_editor_demo/ai/article_edit_service_test.dart`
Expected: `All 3 tests passed!`

> **若 hasEdit=true 用例失败**（modifiedBlock 为 null）：说明测试里手写的 `modifiedToml` 不是 `NoteFactory.fromTomlString` 能解析的合法 TOML。调整 `_editResponse` 里的 toml 字符串，确保它是 `noteFactory.toTomlString(someBlock)` 的真实输出形状（`content = { spans = [...] }`，不是扁平字符串）。可在测试里先 `print(noteFactory.toTomlString(Block(id:'root', type: PageType())))` 拿真实形状再填回。

- [ ] **Step 5: 静态分析**

Run: `flutter analyze lib/lab/demos/block_editor_demo/ai/article_edit_service.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/lab/demos/block_editor_demo/ai/article_edit_service.dart test/lab/demos/block_editor_demo/ai/article_edit_service_test.dart
git commit -m "feat(block-editor): add ArticleEditService wrapping article/edit endpoint" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `DiffViewer`

方案 A diff 展示：原样渲染，`+` 绿、`-` 红、`@@` 灰、上下文默认。纯 UI，widget test 验证渲染。

**Files:**
- Create: `lib/lab/demos/block_editor_demo/ai/diff_viewer.dart`
- Test: `test/lab/demos/block_editor_demo/ai/diff_viewer_test.dart`

- [ ] **Step 1: 写失败测试** — 创建 `test/lab/demos/block_editor_demo/ai/diff_viewer_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/block_editor_demo/ai/diff_viewer.dart';

void main() {
  testWidgets('renders added/removed/context lines with distinct colors',
      (tester) async {
    const diff = '@@ -1,2 +1,2 @@\n context line\n-old\n+new';

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: DiffViewer(diff: diff)),
    ));

    // 3 行文本（@@ 不算 diff 体行，按实际渲染计；这里验证关键 token 存在）
    expect(find.textContaining('old'), findsOneWidget);
    expect(find.textContaining('new'), findsOneWidget);
    expect(find.textContaining('context'), findsOneWidget);
  });

  testWidgets('renders nothing visible when diff is empty', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: DiffViewer(diff: '')),
    ));
    expect(find.byType(ListView), findsNothing);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/lab/demos/block_editor_demo/ai/diff_viewer_test.dart`
Expected: FAIL — `DiffViewer` 未定义。

- [ ] **Step 3: 实现** — 创建 `lib/lab/demos/block_editor_demo/ai/diff_viewer.dart`：

```dart
import 'package:flutter/material.dart';

/// 方案 A diff 展示：按行渲染，`+` 绿、`-` 红、`@@` 灰、其余默认。
/// monospace，紧凑。
class DiffViewer extends StatelessWidget {
  final String diff;
  final int maxLines;

  const DiffViewer({super.key, required this.diff, this.maxLines = 12});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = diff.isEmpty ? <String>[] : diff.split('\n');

    if (lines.isEmpty) return const SizedBox.shrink();

    return Container(
      constraints: BoxConstraints(maxHeight: 28.0 * maxLines),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: lines.length,
        itemBuilder: (context, i) {
          final line = lines[i];
          return Text(
            line.isEmpty ? ' ' : line,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              height: 1.4,
              color: _colorFor(line, theme),
            ),
          );
        },
      ),
    );
  }

  Color _colorFor(String line, ThemeData theme) {
    if (line.startsWith('+++') || line.startsWith('---')) {
      return theme.colorScheme.onSurfaceVariant;
    }
    if (line.startsWith('+')) {
      return Colors.green.shade700;
    }
    if (line.startsWith('-')) {
      return Colors.red.shade700;
    }
    if (line.startsWith('@@')) {
      return theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6);
    }
    return theme.colorScheme.onSurface;
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/lab/demos/block_editor_demo/ai/diff_viewer_test.dart`
Expected: `All 2 tests passed!`

- [ ] **Step 5: 静态分析**

Run: `flutter analyze lib/lab/demos/block_editor_demo/ai/diff_viewer.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/lab/demos/block_editor_demo/ai/diff_viewer.dart test/lab/demos/block_editor_demo/ai/diff_viewer_test.dart
git commit -m "feat(block-editor): add DiffViewer for git unified diff display" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: 改造 `EditorState`（sendAiPrompt + confirmAiResult + 状态字段）

**Files:**
- Modify: `lib/lab/demos/block_editor_demo/state.dart`

这个改造涉及 ChangeNotifier 异步状态机，单测成本高——核心逻辑（转换/分支）已被 Task 1/3 的单测覆盖。本 task 依赖手动验证 + 编译通过。

- [ ] **Step 1: 加 import 和状态字段**

打开 `lib/lab/demos/block_editor_demo/state.dart`。在文件顶部 import 块加：

```dart
import 'ai/ai_settings_store.dart';
import 'ai/article_edit_service.dart';
```

（已有 `import 'ai/ai_models.dart';`，保持不变。）

在 `EditorState` 类内，`final Map<String, List<Block>> _aiResults = {};`（约 `:34`）下方加：

```dart
  /// AI 编辑的 diff 缓存：blockId → diff 文本（hasEdit=true 时有值）。
  final Map<String, String> _aiDiff = {};

  /// AI 错误信息（未配置/请求失败等）。
  String? _aiError;

  /// 注入的 article/edit 服务（null = 未接入后端）。
  ArticleEditService? _articleEditService;

  /// 当前 AI 配置。
  AiSettings _aiSettings = const AiSettings();
```

- [ ] **Step 2: 加 getter 和 setter**

在 `bool isAiShowingResult(String blockId) => _aiResults.containsKey(blockId);`（约 `:84`）下方加：

```dart
  /// 某 block 的 AI diff（无则 null）。
  String? aiDiffFor(String blockId) => _aiDiff[blockId];

  /// 当前 AI 错误信息（UI 展示用，读后清空）。
  String? get aiError => _aiError;

  /// 是否已配置 apiKey。
  bool get isAiConfigured => _aiSettings.isConfigured && _articleEditService != null;

  /// 注入 article/edit 服务。
  void setArticleEditService(ArticleEditService? service) {
    _articleEditService = service;
  }

  /// 更新 AI 配置（设置页保存后调用）。
  void updateAiSettings(AiSettings settings) {
    _aiSettings = settings;
    notifyListeners();
  }
```

- [ ] **Step 3: 改造 `sendAiPrompt`**（替换约 `:100-133` 的整段 mock 方法）

把现有的 `Future<void> sendAiPrompt(String blockId, String prompt) async { ... }` 整段替换为：

```dart
  /// 发送 AI 请求 — 调用后端 article/edit 做全文编辑。
  Future<void> sendAiPrompt(String blockId, String prompt) async {
    if (prompt.isEmpty) return;

    // 未接入或未配置 → 提示
    if (_articleEditService == null || !_aiSettings.isConfigured) {
      _aiError = '请先在设置中配置 API Key';
      _activeAiBarBlockId = null;
      notifyListeners();
      return;
    }

    // 进入 loading
    _activeAiBarBlockId = null;
    _aiLoadingBlockId = blockId;
    _aiResults.remove(blockId);
    _aiDiff.remove(blockId);
    _aiError = null;
    notifyListeners();

    try {
      // 构造整篇笔记的 Block（PageType root + 当前所有 block 作 children）
      final root = _noteFactory.createBlock(
        const PageType(),
        id: _noteId ?? _noteFactory.generateId(),
        content: RichText.text(_extractTitle()),
        children: List<Block>.of(_blocks),
      );

      final result = await _articleEditService!.edit(
        rootNote: root,
        prompt: prompt,
        settings: _aiSettings,
      );

      if (result.hasEdit && result.modifiedBlock != null) {
        _aiDiff[blockId] = result.diff;
        _aiResults[blockId] = result.modifiedBlock!.children;
      } else {
        // 纯问答：conclusion 作为单个段落
        _aiResults[blockId] = [
          _noteFactory.createBlock(
            const ParagraphType(),
            content: RichText.text(result.conclusion),
          ),
        ];
      }
    } catch (e) {
      _aiError = 'AI 请求失败：$e';
    } finally {
      _aiLoadingBlockId = null;
      notifyListeners();
    }
  }
```

- [ ] **Step 4: 改造 `confirmAiResult`**（替换约 `:136-149`）

把现有的 `void confirmAiResult(String blockId) { ... }` 整段替换为：

```dart
  /// 确认 AI 回复：用结果替换整篇笔记（全文编辑语义）。
  /// 若无 diff（纯问答结果），退化为把单段结论追加到当前 block 之后。
  void confirmAiResult(String blockId) {
    final blocks = _aiResults.remove(blockId);
    final hasDiff = _aiDiff.remove(blockId) != null;
    if (blocks == null || blocks.isEmpty) return;

    if (hasDiff) {
      // 全文替换
      _blocks
        ..clear()
        ..addAll(blocks);
    } else {
      // 纯问答：插入到当前 block 之后
      final idx = _blocks.indexWhere((b) => b.id == blockId);
      if (idx >= 0) {
        _blocks.insertAll(idx + 1, blocks);
      } else {
        _blocks.addAll(blocks);
      }
    }

    _selectedId = blocks.isNotEmpty ? blocks.first.id : null;
    notifyListeners();
    _save();
  }
```

- [ ] **Step 5: 清理 `clearAiResult` 同时清 diff**

把 `void clearAiResult(String blockId)`（约 `:152`）改为：

```dart
  /// 清除 AI 回复结果（及对应的 diff）。
  void clearAiResult(String blockId) {
    _aiResults.remove(blockId);
    _aiDiff.remove(blockId);
    _aiError = null;
    notifyListeners();
  }
```

- [ ] **Step 6: 编译 + 静态分析**

Run: `flutter analyze lib/lab/demos/block_editor_demo/state.dart`
Expected: `No issues found!`（若有 `_aiError never used` 之类，正常——Task 6/7 会消费它）。

- [ ] **Step 7: Commit**

```bash
git add lib/lab/demos/block_editor_demo/state.dart
git commit -m "refactor(block-editor): wire sendAiPrompt to article/edit, confirmAiResult to full-replace" -m "- sendAiPrompt calls ArticleEditService (was mock)
- confirmAiResult replaces whole note when hasEdit (was insert-after)
- add _aiDiff/_aiSettings/_aiError/_articleEditService state" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: `card.dart._buildAiResult` 接入 `DiffViewer` + 错误提示

**Files:**
- Modify: `lib/lab/demos/block_editor_demo/card.dart`

- [ ] **Step 1: 加 import**

在 `card.dart` 顶部 import 块（已有 `import 'ai/ai_bar.dart';` `import 'ai/ai_conversation.dart' show AiConversationOverlay;`）加：

```dart
import 'ai/diff_viewer.dart';
```

- [ ] **Step 2: 在 `_buildAiResult` 顶部插入 diff + 错误展示**

定位 `Widget _buildAiResult(BuildContext context, List<Block> blocks) {`（约 `:333`）。在方法体开头的 `final colorScheme = ...` `final noteRoot = ...` `final blockText = ...` 之后、`return Container(` 之前，没有改动 Container 本身——而是把 diff 作为 Column 的第一个子项插入。

找到 `_buildAiResult` 里 `child: Column(` 下的 `crossAxisAlignment: CrossAxisAlignment.start,` 然后 `children: [`，在 `// 逐个渲染每个 Block` 注释（约 `:347`）**之前**插入：

```dart
          // diff 展示（仅 hasEdit 时）
          final diff = widget.editorState.aiDiffFor(widget.block.id);
          if (diff != null && diff.isNotEmpty) ...[
            DiffViewer(diff: diff),
            const SizedBox(height: 6),
          ],
          // 错误提示
          if (widget.editorState.aiError != null) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                widget.editorState.aiError!,
                style: TextStyle(fontSize: 12, color: colorScheme.onErrorContainer),
              ),
            ),
            const SizedBox(height: 6),
          ],
```

- [ ] **Step 3: 编译 + 静态分析**

Run: `flutter analyze lib/lab/demos/block_editor_demo/card.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/lab/demos/block_editor_demo/card.dart
git commit -m "feat(block-editor): show DiffViewer + error in _buildAiResult" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: `block_editor_demo` 注入 service + AppBar 配置入口

**Files:**
- Modify: `lib/lab/demos/block_editor_demo/block_editor_demo.dart`

- [ ] **Step 1: 加 import**

在 `block_editor_demo.dart` 顶部 import 块加：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../api/providers/api_providers.dart';
import 'ai/ai_settings_store.dart';
import 'ai/article_edit_service.dart';
```

- [ ] **Step 2: 加配置 sheet 方法**

在 `_BlockEditorDemoState` 类内（`_showImportMdTextDialog` 方法附近）加：

```dart
  Future<void> _showAiSettingsSheet() async {
    final store = AiSettingsStore();
    final current = await store.load();
    if (!mounted) return;

    final apiKeyCtl = TextEditingController(text: current.apiKey);
    final modelCtl = TextEditingController(text: current.model);
    final baseUrlCtl = TextEditingController(text: current.baseUrl);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('AI 配置', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: apiKeyCtl,
              decoration: const InputDecoration(
                labelText: 'API Key',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              obscureText: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: modelCtl,
              decoration: const InputDecoration(
                labelText: '模型名（可选，如 glm-4.7）',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: baseUrlCtl,
              decoration: const InputDecoration(
                labelText: 'Base URL（可选）',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                await store.save(AiSettings(
                  apiKey: apiKeyCtl.text.trim(),
                  model: modelCtl.text.trim(),
                  baseUrl: baseUrlCtl.text.trim(),
                ));
                _editorState.updateAiSettings(AiSettings(
                  apiKey: apiKeyCtl.text.trim(),
                  model: modelCtl.text.trim(),
                  baseUrl: baseUrlCtl.text.trim(),
                ));
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
```

- [ ] **Step 3: 在 `didChangeDependencies` 注入 service + 加载配置**

把现有 `didChangeDependencies`（约 `:27-42`）改为：

```dart
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_editorStateReady) {
      _editorState = EditorState(
        noteFactory: NoteRootScope.of(context).noteRoot,
      );
      // 注入 ArticleEditService（通过 riverpod 拿 endpoint）
      final container = ProviderScope.containerOf(context);
      final endpoint = container.read(articleEndpointProvider);
      _editorState.setArticleEditService(
        ArticleEditService.forEndpoint(endpoint, _editorState.noteFactorySafe),
      );
      // 加载 AI 配置
      AiSettingsStore().load().then((s) {
        if (mounted) _editorState.updateAiSettings(s);
      });
      _editorState.toolbarFactory.setImportCallbacks(
        onImportMdFile: _importMdFile,
        onImportMdText: _showImportMdTextDialog,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _editorState.init();
      });
    }
  }
```

> **注意**：上面用了 `_editorState.noteFactorySafe`——但 `EditorState` 当前没暴露 `noteFactory`。Step 4 会加这个 getter。

- [ ] **Step 4: 给 `EditorState` 加 `noteFactory` getter**

在 `state.dart` 的 `EditorState` 类内（`final NoteFactory _noteFactory;` 字段，约 `:20`）下方加：

```dart
  /// 暴露 NoteFactory（供外部组装 service）。
  NoteFactory get noteFactorySafe => _noteFactory;
```

- [ ] **Step 5: AppBar 加配置按钮**

在 `block_editor_demo.dart` 的 `build` 方法里，`AppBar` 的 `actions:`（约 `:132-140`）改为：

```dart
            appBar: AppBar(
              title: const Text('块编辑器'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.settings),
                  tooltip: 'AI 配置',
                  onPressed: _showAiSettingsSheet,
                ),
                IconButton(
                  icon: const Icon(Icons.menu_open),
                  onPressed: () {
                    _scaffoldKey.currentState?.openEndDrawer();
                  },
                  tooltip: '笔记列表',
                ),
              ],
            ),
```

- [ ] **Step 6: 编译 + 静态分析**

Run: `flutter analyze lib/lab/demos/block_editor_demo/block_editor_demo.dart lib/lab/demos/block_editor_demo/state.dart`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/lab/demos/block_editor_demo/block_editor_demo.dart lib/lab/demos/block_editor_demo/state.dart
git commit -m "feat(block-editor): inject ArticleEditService via riverpod + AppBar AI config sheet" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: 手动验证 + 最终验收

**Files:** 无代码改动。

- [ ] **Step 1: 全量测试**

Run: `flutter test`
Expected: 全绿（之前 12 + 本次新增：repo 2 + settings 2 + service 3 + diffviewer 2 = 21）。

- [ ] **Step 2: 全量静态分析**

Run: `flutter analyze lib/core/note lib/lab/demos/block_editor_demo`
Expected: `No issues found!`（既有 unrelated warning 可忽略）。

- [ ] **Step 3: 后端未被修改**

Run: `cd D:/DevProjects/my/github/dev_ctr_hello && git status --short lib/ai`
Expected: 空（lib/ai 无改动）。

- [ ] **Step 4: 手动 e2e（真机/模拟器）**

`flutter run` → Lab → 块编辑器：
1. 点 AppBar 齿轮 → 填 apiKey（用后端 service/ai 默认的 deepseek key 或自己的）→ 保存
2. 新建笔记，加 2 个段落（"AI 很强大。" / "但带来挑战。"）
3. 在第一个 block 空内容时按空格 → AiBar 出现 → 输入"把第一段改乐观一些"→ 回车
4. 预期：loading → 显示 DiffViewer（`+`绿/`-`红）+ 修改后的 blocks + 确认按钮
5. 点 ✓ 确认 → 整篇笔记被替换 → 重启 app 确认持久化
6. 再触发一次"这篇主题是什么？"→ 预期：只显示 conclusion 文本（无 diff），确认后追加段落

- [ ] **Step 5: 验收 checklist（对照 spec §11）**

- [ ] `flutter analyze lib/core/note lib/lab/demos/block_editor_demo` 0 error
- [ ] 新增测试全绿（21 用例）
- [ ] 配置 apiKey 后能触发编辑、看到 diff
- [ ] 点应用 → 全文替换 + 持久化
- [ ] 纯问答 → 只展示 conclusion，不展示 diff
- [ ] 未配置 apiKey → 提示去配置
- [ ] 后端 `dev_ctr_hello` 未被修改

- [ ] **Step 6: 无需 commit**（验收步）

---

## 完成准则

全部 8 个 Task 的 checkbox 勾选完毕。
