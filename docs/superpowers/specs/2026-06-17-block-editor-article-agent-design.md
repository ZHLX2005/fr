# block_editor_demo 接入 article/edit Agent 设计

> **状态**：待审核
> **日期**：2026-06-17
> **范围**：`lib/lab/demos/block_editor_demo/` + `lib/core/note/factory.dart` 加 2 个方法。不改后端、不改领域层结构。

---

## 1. 目标

把 `block_editor_demo` 的 AI 功能从 mock 接到真实后端 `/api/v1/article/edit`，实现**全文编辑 + diff 展示**：用户在笔记里输入要求 → 整篇 TOML 发后端 → AI 生成 diff + 修改后全文 → 前端展示 diff → 用户确认后替换整篇。

### 不做什么

- ❌ **不改后端** `dev_ctr_hello`（用户硬约束）
- ❌ **不接其他 agent**（coder/searcher/executor 等 9 个无 endpoint 的 agent 不在范围）
- ❌ **不改领域层** `core/note/core/*`（只给 `NoteFactory` 加 2 个便捷方法）
- ❌ **不统一 chat provider 的 api_client**（独立 scope，本 spec 不碰）
- ❌ **不重写 AI UI**（复用现有 AiBar / AiBubble / AiConversationOverlay / 状态机）

## 2. 动机

TOML 化（已交付，commit `c003ecc`..`b35c33a`）的初衷就是"接入后端 agent，展示 AI 编辑和修改的内容"。本 spec 完成这最后一环：让笔记编辑器真正能调用后端 AI 编辑能力，并把 diff 可视化。

## 3. 现状（已核对）

### 后端（不动）

- `POST /api/v1/article/edit`（`api/ai/v1/ai.go:46`）已暴露
- 请求 `{apiKey, articleToml, prompt, model?, baseUrl?}`，响应 `{diff, conclusion, modified_toml, has_edit}`
- 后端 `article_master` agent（Supervisor：sub_editor + sub_qa）已在内存闭环跑通

### 前端

- ✅ `ArticleEndpoint`（`lib/api/goframe/article/article_endpoint.dart`）封装完整
- ✅ `articleEndpointProvider`（`lib/api/providers/api_providers.dart:41`）走统一 `ApiClient`（含 auth/retry/logging）
- ✅ `NoteRepository` 持有 `_codec`（BlockCodec）+ `_tomlCodec`（TomlCodec）—— 数据转换的基础设施已就绪
- ⚠️ `block_editor_demo` 的 AI UI **已完整挂载**：
  - `card.dart:230,240` AiBar（空格触发，block 级）
  - `card.dart:363` AiConversationOverlay
  - `ai_bubble.dart` AiBubble
  - `state.dart:22-155` 完整 AI 状态机（`_aiConversations`/`_activeAiBarBlockId`/`_aiLoadingBlockId`/`_aiResults`/`sendAiPrompt`/`confirmAiResult`/`clearAiResult`）
- ❌ **唯一 mock 点**：`state.dart:101-133` 的 `sendAiPrompt`——`Future.delayed(1s)` + 假 markdown

### 语义错配（本次解决）

| | 现有 UI 语义 | 后端语义 | 本次决策 |
|---|---|---|---|
| 粒度 | block 级（AiBar 单 block） | 全文（整篇 TOML） | **全文**（触发时取整篇笔记） |
| 结果 | 插入 blockId 之后 | 替换整篇 + diff | **替换整篇 + 展示 diff** |

## 4. 决策记录

| 决策点 | 选择 | 理由 |
|---|---|---|
| 接入语义 | 全文编辑 + diff | 用户初衷"展示 AI 编辑和修改的内容" |
| UI | 复用现有（AiBar/AiBubble/状态机） | UI 已写好且挂载，不重写 |
| apiKey 来源 | demo 独立配置（SharedPreferences） | 用户指定；不与 ai_chat_provider 共享 |
| diff 展示精度 | **方案 A**（原样着色 `+/-` 行） | YAGNI；后端 diff 已是行级可读格式 |
| 数据转换位置 | `NoteRepository` 加 `encodeToml/decodeToml`，`NoteFactory` 暴露 | repository 已持有 codec + tomlCodec，转换最自然 |
| service 依赖获取 | riverpod `articleEndpointProvider` | 已就绪，走统一 ApiClient |

## 5. 架构（数据流）

```
[AiBar 触发] → sendAiPrompt(blockId, prompt)
   │
   ├─ EditorState 构造整篇 Block：PageType(id=_noteId, children=_blocks)
   ├─ NoteFactory.toTomlString(rootBlock) → TOML 字符串
   │
   ├─ ArticleEditService.edit(rootBlock, prompt, aiSettings)
   │     ├─ toTomlString（内部复用 NoteFactory）
   │     ├─ ArticleEndpoint.edit(apiKey, articleToml, prompt, model, baseUrl)
   │     └─ hasEdit ? fromTomlString(modifiedToml)→Block : null
   │
   ├─ hasEdit=true：
   │     ├─ _aiDiff[blockId] = result.diff
   │     └─ _aiResults[blockId] = modifiedBlock.children
   ├─ hasEdit=false：
   │     └─ _aiResults[blockId] = [Paragraph(conclusion)]  // 单段问答
   │
   ├─ [AiBubble 展示] → DiffViewer(diff) + 结论
   │
   └─ [用户点「应用」] → confirmAiResult(blockId)
         ├─ _blocks..clear()..addAll(modifiedBlocks)   // 全文替换
         └─ _save()
```

## 6. 组件

### 6.1 `NoteFactory` 加 2 个方法（`core/note/factory.dart`）

```dart
/// Block 树 → TOML 字符串（含 root）。
/// 用于发给后端 article/edit。
String toTomlString(Block root) => _repository.encodeToml(root);

/// TOML 字符串 → Block 树。解析失败返回 null。
Block? fromTomlString(String toml) => _repository.decodeToml(toml);
```

### 6.2 `NoteRepository` 加 2 个方法（`core/note/persistence/note_repository.dart`）

```dart
/// Block → TOML 字符串（复用已有 _codec + _tomlCodec）。
String encodeToml(Block block) => _tomlCodec.encode(_codec.encode(block));

/// TOML 字符串 → Block。解析失败返回 null。
Block? decodeToml(String toml) {
  try {
    return _codec.decode(_tomlCodec.decode(toml));
  } catch (_) {
    return null;
  }
}
```

### 6.3 新建 `ArticleEditService`（`block_editor_demo/ai/article_edit_service.dart`）

单一职责：Block → TOML → endpoint → TOML → Block，屏蔽转换。

```dart
class ArticleEditService {
  final ArticleEndpoint _endpoint;
  final NoteFactory _noteFactory;

  ArticleEditService(this._endpoint, this._noteFactory);

  Future<ArticleEditResult> edit({
    required Block rootNote,
    required String prompt,
    required AiSettings settings,
  }) async {
    final toml = _noteFactory.toTomlString(rootNote);
    final resp = await _endpoint.edit(
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
    return ArticleEditResult(
      hasEdit: d.hasEdit,
      conclusion: d.conclusion,
      diff: d.diff,
      modifiedBlock: d.hasEdit ? _noteFactory.fromTomlString(d.modifiedToml) : null,
    );
  }
}

class ArticleEditResult {
  final bool hasEdit;
  final String conclusion;
  final String diff;
  final Block? modifiedBlock;  // hasEdit=true 时有效
  const ArticleEditResult({required this.hasEdit, required this.conclusion, required this.diff, this.modifiedBlock});
}

class ArticleEditException implements Exception {
  final String message;
  ArticleEditException(this.message);
  @override String toString() => 'ArticleEditException: $message';
}
```

### 6.4 新建 `AiSettings` + `AiSettingsStore`（`block_editor_demo/ai/ai_settings_store.dart`）

demo 独立配置，不依赖 `ai_chat_provider`。

```dart
class AiSettings {
  final String apiKey;
  final String model;
  final String baseUrl;
  const AiSettings({this.apiKey = '', this.model = '', this.baseUrl = ''});
  bool get isConfigured => apiKey.isNotEmpty;
}

class AiSettingsStore {
  static const _key = 'block_editor_ai_settings';
  Future<AiSettings> load() async { /* SharedPreferences 读 */ }
  Future<void> save(AiSettings s) async { /* SharedPreferences 写 */ }
}
```

### 6.5 新建 `DiffViewer`（`block_editor_demo/ai/diff_viewer.dart`）

方案 A：原样渲染 diff 文本，`+` 行绿、`-` 行红、`@@` 行灰、其余默认。monospace。

### 6.6 改造 `EditorState`（`block_editor_demo/state.dart`）

- 构造函数加可选依赖：`ArticleEditService? articleEditService`、`AiSettingsStore? settingsStore`
- 加字段 `AiSettings _aiSettings`、`Map<String, String> _aiDiff`（blockId → diff）
- `sendAiPrompt` 改真实调用（见 §7）
- `confirmAiResult` 改全文替换（见 §7）
- 加 `get aiDiff[blockId]`、`isConfigured` 等 getter

### 6.7 改造 `card.dart`

AI 结果展示区（AiBubble 附近）接入 `DiffViewer`：当 `_aiDiff[blockId]` 非空时显示 diff + 「应用/放弃」按钮。

### 6.8 改造 `block_editor_demo.dart`

- AppBar 加齿轮 icon → 配置 sheet（apiKey/model/baseUrl 表单 → `AiSettingsStore.save`）
- `EditorState` 创建时注入 `ArticleEditService`（通过 riverpod `articleEndpointProvider`）+ `AiSettingsStore`
- 启动时 `settingsStore.load()` → EditorState

## 7. 关键改造伪代码

### `sendAiPrompt`（state.dart:101）

```dart
Future<void> sendAiPrompt(String blockId, String prompt) async {
  if (prompt.isEmpty) return;
  if (_articleEditService == null || !_aiSettings.isConfigured) {
    // 未配置：提示用户去设置
    _aiError = '请先配置 AI API Key';
    notifyListeners();
    return;
  }

  _activeAiBarBlockId = null;
  _aiLoadingBlockId = blockId;
  _aiResults.remove(blockId);
  _aiDiff.remove(blockId);
  _aiError = null;
  notifyListeners();

  try {
    final root = _noteFactory.createBlock(
      const PageType(),
      id: _noteId ?? _noteFactory.generateId(),
      children: List.of(_blocks),
    );
    final result = await _articleEditService!.edit(
      rootNote: root, prompt: prompt, settings: _aiSettings,
    );

    if (result.hasEdit && result.modifiedBlock != null) {
      _aiDiff[blockId] = result.diff;
      _aiResults[blockId] = result.modifiedBlock!.children;
    } else {
      _aiResults[blockId] = [
        _noteFactory.createBlock(const ParagraphType(), content: RichText.text(result.conclusion)),
      ];
    }
  } catch (e) {
    _aiError = e.toString();
  } finally {
    _aiLoadingBlockId = null;
    notifyListeners();
  }
}
```

### `confirmAiResult`（state.dart:136）

```dart
void confirmAiResult(String blockId) {
  final blocks = _aiResults.remove(blockId);
  _aiDiff.remove(blockId);
  if (blocks == null) return;
  _blocks
    ..clear()
    ..addAll(blocks);   // 全文替换
  _selectedId = blocks.isNotEmpty ? blocks.first.id : null;
  notifyListeners();
  _save();
}
```

## 8. 错误处理

| 场景 | 行为 |
|---|---|
| 未配置 apiKey | `_aiError = '请先配置'`，notifyListeners，不调后端 |
| 网络失败 / endpoint 返回非 success | catch → `_aiError` 展示 |
| `fromTomlString` 解析失败（modifiedToml 损坏） | `modifiedBlock=null`，降级为展示 conclusion + 提示"解析失败" |
| 后端 hasEdit=true 但 modifiedToml 为空 | 视为异常，走 catch |

## 9. 测试策略

| 测试 | 文件 | 内容 |
|---|---|---|
| `NoteRepository.encodeToml/decodeToml` roundtrip | `test/core/note/persistence/note_repository_test.dart`（已有，加用例） | Block→TOML→Block 等价 |
| `ArticleEditService` | `test/lab/demos/block_editor_demo/ai/article_edit_service_test.dart`（新建） | mock ArticleEndpoint，验证 hasEdit 分支 + Block 转换 + 异常 |
| `AiSettingsStore` | 同上目录 | SharedPreferences 读写（用临时 path） |

> `sendAiPrompt` 涉及 UI 状态机 + 异步，单测成本高，依赖手动验证 + service 层测试覆盖核心逻辑。

## 10. 不做（YAGNI）

- ❌ diff 富展示（对照原文映射 block）——方案 A 够用
- ❌ 多轮对话上下文（AiConversationOverlay 的历史）——首发只单轮编辑
- ❌ 流式输出——endpoint 是非流式
- ❌ 撤销栈——`confirmAiResult` 替换后不可撤销（save 已持久化，靠笔记历史/手动恢复）
- ❌ 错误重试 UI——失败展示 `_aiError`，用户手动重发

## 11. 验收标准

- [ ] `flutter analyze lib/core/note lib/lab/demos/block_editor_demo` 0 error
- [ ] 新增 3 个测试文件全绿（repository roundtrip + service + settings store）
- [ ] demo 里配置 apiKey 后，在 block 触发 AiBar 输入"把第一段改乐观"→ 看到 diff（绿/红行）
- [ ] 点「应用」→ 整篇笔记被替换为 modifiedToml 内容 + 持久化（重启可读回）
- [ ] 纯问答（如"这篇主题是什么"）→ 展示 conclusion，不展示 diff，不替换
- [ ] 未配置 apiKey → 提示去配置，不发请求
- [ ] 后端 `dev_ctr_hello` 未被修改（git status 验证）

## 12. 已知局限

- **demo 级实现**：本 spec 只改 `block_editor_demo`（lab demo），不是正式产品功能。正式接入需迁移到 `screens/` + 统一 chat provider 架构——独立工作。
- **ApiKey 明文存 SharedPreferences**：demo 用，生产应加密（参照 `lib/core/crypto/secret.go` 后端做法，前端另做）。
- **全文替换无确认粒度**：应用即整篇替换，无"部分应用"。YAGNI。
