# 块编辑器 TOML 格式规范

> 版本：1.0 · 适用范围：`lib/lab/demos/block_editor_demo/` + `lib/core/note/`
> 单篇笔记以 TOML 文件持久化（`{noteId}.toml`），后端 agent 工具链也以 TOML 作为文章传输格式。
> 本文档定义 **Block ↔ TOML 互转** 的完整规范，以及**有效性检查约束**。

---

## 1. 文件结构

每个笔记是一个 TOML 文件，**根节点就是一个 `Block`**（`type='page'`），其 `children` 即正文 blocks 列表。

```toml
# 顶层表：根 Block
id = '1d030206-0704-440b-8a0e-0f08080b033d'      # 必填：根 block id
type = 'page'                                    # 必填：固定 'page'
created_at = 1781771051849                        # 必填：创建时间，毫秒
updated_at = 1781771051849                        # 必填：更新时间，毫秒

[content]                                         # 必填：根 block 的富文本（标题/默认内容）

[[content.spans]]                                 # content 是表，spans 是该表内的数组
text = '哈哈哈哈哈哈哈'

# data 字段：PageType 无专属数据（空）
[data]

# properties 字段：用户自定义属性（默认空）
[properties]

# 顶级 children：[[children]] 是根 block 的子块数组
[[children]]
id = 'e8e9e8ef-e9ea-4be5-a4e7-e5e2e3e1e0ff'
type = 'paragraph'
created_at = 1781696064618
updated_at = 1781696067588
children = []

[children.content]

[[children.content.spans]]
text = '哈哈哈哈哈哈哈'

[children.data]

[children.properties]

[[children]]
id = '93959b9c-9c9f-4e92-9390-9097969293ec'
type = 'paragraph'
...
```

---

## 2. Block 通用 schema

每个 block 编码为 TOML 时包含以下字段（顺序固定）：

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `id` | string | ✅ | 全局唯一块标识。UUID 格式（hex with dashes），由 `NoteFactory.generateId()` 生成 |
| `type` | string | ✅ | 块类型 tag。必须是 §5 列出的 19 种之一 |
| `content` | table | ✅ | 富文本内容，schema 见 §3 |
| `children` | array of table | ✅ | 子块列表。不可变树；嵌套深度无硬限制（按规范建议 ≤ 5） |
| `data` | table | ✅ | 类型专属数据，schema 见 §5 |
| `properties` | table | ✅ | 用户自定义键值对，schema 见 §4 |
| `created_at` | integer | ✅ | 创建时间，Unix 毫秒时间戳 |
| `updated_at` | integer | ✅ | 更新时间，Unix 毫秒时间戳 |

### 2.1 序列化顺序约定

`BlockCodec.encode` 输出字段顺序固定为：

```dart
{
  'id': ...,
  'type': ...,
  'content': ...,
  'children': [...],
  'data': ...,
  'properties': ...,
  'created_at': ...,
  'updated_at': ...,
}
```

TOML 编码后字段顺序为字典序（`toml` 包行为），不在协议保证范围内，**消费方不应依赖字段顺序**。

---

## 3. 富文本（RichText） schema

Block 的 `content` 是一个 table：

```toml
[block_id.content]                       # 此表名固定为 "${parentKey}.content"
                                          # （根 block 用 [content]，子 block 用 [children.content]）

[[block_id.content.spans]]                # spans 是数组，每个元素是一个 span
text = 'plain text'
# format 可选。带格式时：
# format = { type = 'bold' }
```

### 3.1 Span

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `text` | string | ✅ | 文本内容。允许空字符串 `''`，表示空 span |
| `format` | table | ❌ | 内联格式，schema 见 §6。缺省 = 纯文本 |

### 3.2 空 RichText 表示

空内容用 `spans = []`（in-line 数组），**不**用 `[[spans]]` 空数组。

```toml
[content]
spans = []          # ← 正确：空内容

[content]

[[content.spans]]   # ← 错误：没有元素却有 [[]] 头
```

实际后端 LLM 生成 TOML 时经常使用空表头 + `[[spans]]` 形式。**前端解码需容错**：见 §7 兼容性。

---

## 4. properties schema

`properties` 是用户自定义键值对表，**键名推荐** 遵循：

- 全小写 + snake_case
- 长度 ≤ 64 字符
- 不可与 `BlockCodec.encode` 保留键（`id/type/content/children/data/created_at/updated_at`）同名

典型用法：

```toml
[children.properties]
custom_key = 'value'
priority = 3
is_pinned = true
```

**协议不约束**具体 key 集合，由应用层定义。

---

## 5. Block Type 标准含义

### 5.1 总览（19 种）

| `tag` | 类名 | `canHaveChildren` | `containerOnly` | `multiline` | 专属 data 字段 |
|---|---|---|---|---|---|
| `page` | `PageType` | ✅ | ✅ | ❌ | 无 |
| `paragraph` | `ParagraphType` | ❌ | ❌ | ❌ | 无 |
| `heading` | `HeadingType` | ❌ | ❌ | ❌ | `level: int` |
| `todo` | `TodoType` | ❌ | ❌ | ❌ | `checked: bool` |
| `toggle` | `ToggleType` | ✅ | ❌ | ❌ | 无 |
| `bullet_list_item` | `BulletListItemType` | ✅ | ❌ | ❌ | 无 |
| `ordered_list_item` | `OrderedListItemType` | ✅ | ❌ | ❌ | `number: int` |
| `quote` | `QuoteType` | ❌ | ❌ | ❌ | 无 |
| `code` | `CodeType` | ❌ | ❌ | ✅ | `language: string` |
| `divider` | `DividerType` | ❌ | ✅ | ❌ | 无 |
| `callout` | `CalloutType` | ❌ | ❌ | ❌ | `icon: string` |
| `image` | `ImageType` | ❌ | ❌ | ❌ | `src, caption?, width?, height?` |
| `embed_card` | `EmbedCardType` | ❌ | ❌ | ❌ | `title, subtitle, icon, sourceBlockId` |
| `bookmark` | `BookmarkType` | ❌ | ❌ | ❌ | `url, title, description, favicon` |
| `equation` | `EquationType` | ❌ | ❌ | ❌ | `latex: string` |
| `database` | `DatabaseType` | ✅ | ❌ | ❌ | 无 |
| `column_list` | `ColumnListType` | ✅ | ❌ | ❌ | 无 |
| `column` | `ColumnType` | ✅ | ❌ | ❌ | `ratio: double` |
| `synced_block` | `SyncedBlockType` | ❌ | ❌ | ❌ | `refBlockId: string` |

### 5.2 各 type 详细定义

#### `page` — 文档根

```toml
id = '...'
type = 'page'
created_at = 1781771051849
updated_at = 1781771051849

[content]
# 根 block 的 content 承载笔记标题
[[content.spans]]
text = '我的笔记标题'

[data]            # PageType 无 data，输出空表头
[properties]      # 用户自定义属性

[[children]]
# 文档正文 blocks
```

**约束**：
- 每个笔记文件**恰好一个** `type='page'` 块（根）
- `containerOnly=true` → 用户编辑态不会直接显示文本字段
- `onEnterType=null` → 不支持按 Enter 创建新 page

#### `paragraph` — 段落

```toml
id = '...'
type = 'paragraph'
created_at = ...
updated_at = ...
children = []

[content]
[[content.spans]]
text = '这是普通段落'

[data]            # 无 data
[properties]
```

**用途**：默认文本块。Markdown 中无标记的文本行。

#### `heading` — 标题

```toml
id = '...'
type = 'heading'
created_at = ...
updated_at = ...
children = []

[content]
[[content.spans]]
text = '一级标题'

[data]
level = 1           # 1-3；缺省 1

[properties]
```

**约束**：
- `level` ∈ `{1, 2, 3}`。超出范围或缺失 → 视作 `level=1`
- Markdown 触发：`# ` / `## ` / `### `

#### `todo` — 待办

```toml
id = '...'
type = 'todo'
created_at = ...
updated_at = ...
children = []

[content]
[[content.spans]]
text = '买菜'

[data]
checked = false      # 缺省 false

[properties]
```

**约束**：
- Markdown 触发：`[ ] `（未勾选）/ `[x] `（已勾选）
- `onEnterType = TodoType(checked: false)` → 按 Enter 创建新未勾选 todo

#### `toggle` — 折叠块

```toml
id = '...'
type = 'toggle'
created_at = ...
updated_at = ...

[content]
[[content.spans]]
text = '点我展开'

[data]            # 无
[properties]

[[children]]
# 折叠内容
id = '...'
type = 'paragraph'
...
```

#### `bullet_list_item` — 无序列表项

```toml
id = '...'
type = 'bullet_list_item'
created_at = ...
updated_at = ...

[content]
[[content.spans]]
text = '列表项内容'

[data]            # 无
[properties]

[[children]]
# 嵌套子项（缩进显示）
```

**Markdown 触发**：`- ` 或 `* `

#### `ordered_list_item` — 有序列表项

```toml
[data]
number = 3          # 显示编号；缺省 1
```

**Markdown 触发**：`1. ` / `2. ` / ...

#### `quote` — 引用

**Markdown 触发**：`> `

#### `code` — 代码块

```toml
[data]
language = 'python'  # 缺省 ''（无语言）
```

**约束**：
- `multiline=true` → TextField 允许多行
- Markdown 触发：```` ```python ````（反引号 + 语言）
- `onEnterType=null` → 代码块内按 Enter 不创建新 code 块

#### `divider` — 分隔线

```toml
id = '...'
type = 'divider'
created_at = ...
updated_at = ...
children = []         # 不允许有 children
                       # content 强制为空
[data]            # 无
[properties]
```

**约束**：
- `containerOnly=true` → 无文本字段
- `onEnterType=null` → 按 Enter 不创建新 divider
- Markdown 触发：`---`

#### `callout` — 高亮提示块

```toml
[data]
icon = '💡'           # emoji 或图标名；缺省 ''
```

#### `image` — 图片

```toml
[data]
src = 'https://...'        # 必填，URL 或本地路径
caption = '图说'           # 可选
width = 800.0              # 可选
height = 600.0             # 可选
```

**约束**：
- `caption/width/height` 缺省时**不输出**该字段（见 §7 兼容性）
- `showQuickDelete=true`（非 containerOnly，但无 TextField）

#### `embed_card` — 嵌入卡片

```toml
[data]
title = '卡片标题'
subtitle = '副标题'
icon = '🔗'
sourceBlockId = 'uuid'   # 源 block id（用于跳回）
```

#### `bookmark` — 书签链接

```toml
[data]
url = 'https://...'
title = '...'
description = '...'
favicon = 'https://...'
```

#### `equation` — 数学公式

```toml
[data]
latex = 'E = mc^2'
```

#### `database` — 数据库视图

```toml
# 容器，承载 schema + rows
```

#### `column_list` + `column` — 多栏布局

```toml
[[children]]
id = '...'
type = 'column_list'
...

[[children]]
id = '...'
type = 'column'
[data]
ratio = 0.5             # 占栏宽度比例；缺省 1.0
...
```

**约束**：`column` 必须放在 `column_list` 下。`ratio` 总和应等于 `column_list` 的子项数。

#### `synced_block` — 同步块（引用）

```toml
[data]
refBlockId = 'uuid-of-source-block'
```

`SyncedBlock` 是其他 block 的**只读引用**，修改源时同步更新。

---

## 6. Inline Format 标准含义

Span 的 `format` 字段支持 7 种内联格式：

| `type` | 类名 | 必填 data 字段 | 用途 |
|---|---|---|---|
| `bold` | `BoldFormat` | 无 | **加粗** |
| `italic` | `ItalicFormat` | 无 | *斜体* |
| `strikethrough` | `StrikethroughFormat` | 无 | ~~删除线~~ |
| `inline_code` | `InlineCodeFormat` | 无 | `行内代码` |
| `color` | `ColorFormat` | `color: string` | 文字颜色（hex `#RRGGBB` 或命名色） |
| `link` | `LinkFormat` | `url: string` | 超链接 |
| `mention` | `MentionFormat` | `block_id: string` | @提及 block |

**TOML 序列化示例**：

```toml
[[content.spans]]
text = '普通'

[[content.spans]]
text = '加粗'
format = { type = 'bold' }                    # 无 data 字段的格式

[[content.spans]]
text = '链接'
format = { type = 'link', url = 'https://...' }

[[content.spans]]
text = '#FF0000'
format = { type = 'color', color = '#FF0000' }

[[content.spans]]
text = '@block-x'
format = { type = 'mention', block_id = 'uuid' }
```

⚠️ **命名差异**：`MentionFormat` 序列化用 `block_id`（snake_case），其他 format 都用 camelCase（如 `url`）。这是已知的**历史不一致**，前端 `InlineFormatRegistry` 已统一处理。

---

## 7. 有效性检查约束

### 7.1 必填字段缺失

| 字段缺失 | 行为 |
|---|---|
| `id` | 解析时**生成 fallback uuid**（hex32）。原 block id 丢失，diff/mentions 可能失效 |
| `type` | 默认 `paragraph` |
| `content` | 默认 `RichText.empty()` |
| `children` | 默认 `[]` |
| `data` | 默认 `{}` |
| `properties` | 默认 `{}` |
| `created_at` | 默认 `DateTime.now()` |
| `updated_at` | 默认 `DateTime.now()` |

### 7.2 type 未知值

`BlockTypeRegistry.resolve` 遇到未知 `type` 时**抛 `ArgumentError`**。当前 `BlockCodec.decode` 已在 `_typeRegistry.resolve` 内部抛出，被 `TomlCodec.decode` 包裹后整段 TOML 解析失败。

**建议**：
- LLM 输出未授权 type 时，前端 fallback 到 `paragraph` 而不是整体失败
- 待办：在 `BlockCodec.decode` 加 try/catch 包装 `_typeRegistry.resolve`

### 7.3 data 字段类型错误

当前 `fromData` 实现：

```dart
HeadingType.fromData: level: data['level'] as int? ?? 1
CodeType.fromData: language: data['language'] as String? ?? ''
```

类型不匹配时（`as int` 失败）**抛 TypeError**，整段解码失败。**待办**：用更鲁棒的 `data['level'] as num?` 转换。

### 7.4 content 表的两种合法形式

| 形式 | 例子 | 状态 |
|---|---|---|
| 空数组 | `[content]\nspans = []` | ✅ 合法 |
| 空表头 | `[content]\n\n[[content.spans]]\n...` | ✅ 合法 |
| 缺 `[content]` 表 | （外层直接 `[[content.spans]]`） | ❌ TOML 语法错 |
| 缺 `[[content.spans]]` 头但有 `text = ...` | | ❌ TOML 语法错 |

后端 LLM 经常输出第二种（空 `[[content.spans]]` 形式），**前端的 `toml` 包需支持**。已验证：当前实现兼容。

### 7.5 properties 空表

`[properties]` 可省略（不写），但写了**必须为空或键值对**，不能是 `properties = null`。

### 7.6 children 嵌套深度

**协议无硬限制**，但 TOML 表名（`[children.children.children.children...]`）随深度增长，**实际建议 ≤ 5 层**。深度过深会让 git diff 难以阅读。

### 7.7 重复 id

**未检查**。同一文件内不同 block 出现相同 id 是非法状态（block 唯一性由 id 决定），但当前未做唯一性校验。**待办**：加载时扫描 id 冲突。

---

## 8. 编码器实现要点

### 8.1 Block ↔ Map（领域层）

`BlockCodec.encode` 输出字段顺序固定（见 §2.1）。`BlockCodec.decode` 在 id 缺失时**已实现** fallback（2026-06-18 修复）。

### 8.2 Map ↔ TOML（持久化层）

`TomlCodec.encode` 用 `TomlDocument.fromMap(map).toString()`。  
`TomlCodec.decode` 用 `TomlDocument.parse(toml).toMap()`。  
任一步失败抛 `TomlException`。

### 8.3 字符串字段引号

`toml` 包 v0.18.0 序列化为 **单引号字面量**（`text = 'foo'`），不是双引号。  
后端 LLM 偶尔输出双引号（`text = "foo"`）也能被 `toml` 包解析为字面量，**兼容性 OK**。

### 8.4 字段命名风格

| 风格 | 字段 |
|---|---|
| snake_case | `created_at`, `updated_at`, `source_block`（`MentionFormat`） |
| camelCase | 其他所有（`refBlockId`, `sourceBlockId`, `data`, `properties`） |

⚠️ `MentionFormat` 用 `block_id` 而其他用 `blockId` 是已知不一致。**新增字段建议用 snake_case**（与 Python 生态保持一致，且后端 eino agent 的 prompt 示例用 snake_case）。

---

## 9. 兼容性矩阵

| 兼容性维度 | 前端 v1 | 后端 LLM 输出 | 状态 |
|---|---|---|---|
| `id` 字段缺失 | fallback uuid | 可能缺失 | ✅ 2026-06-18 修 |
| `properties` 表缺失 | 默认 `{}` | 通常有 | ✅ |
| `data` 表缺失 | 默认 `{}` | 通常有 | ✅ |
| 多余字段（`extra`） | 忽略 | 偶尔有 | ✅（toml 解析后 `as` 不抛） |
| 未知 `type` | 抛 `ArgumentError` | 偶尔有 | ❌ 待办 |
| `[content]` 空表头 | ✅ | 常见 | ✅ |
| `spans = []` 形式 | ✅ | 偶尔 | ✅ |
| `level: '1'`（字符串） | TypeError | 偶尔 | ❌ 待办 |
| 字段顺序 | 协议无关 | — | ✅ |

---

## 10. 已知 bug 与待办

| 编号 | 问题 | 影响 | 修法 |
|---|---|---|---|
| B-1 | 未知 `type` 抛 `ArgumentError` → 整文件解析失败 | LLM 偶尔输出未授权 type | `BlockCodec.decode` 加 fallback 到 `paragraph` |
| B-2 | `data['level'] as int` TypeError on string `'1'` | 字段类型不严格 | 改用 `num?` + `toInt()` |
| B-3 | `id` 冲突未检测 | 理论上可能 | 加载时扫描 |
| B-4 | `MentionFormat` 字段名 `block_id` 与其他不一致 | 跨端互操作易错 | 选 snake_case 为标准，迁移 |
| B-5 | TOML 行号超出 1-indexed 自然序号 | 后端 agent 提示 LLM 加行号 | 保持现状，作为 LLM 工具 |

---

## 11. 与后端 agent 的协议

后端 `article_master` agent 收到 TOML 时会**添加行号**作为提示：

```diff
@@ -10,1 +10,1 @@
-content = "旧"
+content = "新"
```

行号从 1 开始，**与编辑器实际行号一致**。LLM 输出的 `apply_article_diff` 工具调用会基于此行号生成 diff。

`article_master` agent 流程见 `lib/api/goframe/article/article_endpoint.dart` 顶部 doc。

---

## 12. 工具链

| 操作 | 入口 | 关键文件 |
|---|---|---|
| 笔记 → TOML 字符串 | `NoteFactory.toTomlString(block)` | `lib/core/note/factory.dart:81` |
| TOML 字符串 → 笔记 | `NoteFactory.fromTomlString(toml)` | `lib/core/note/factory.dart:84` |
| 笔记文件读 | `NoteRepository.readNote(id)` | `lib/core/note/persistence/note_repository.dart:222` |
| 笔记文件写 | `NoteRepository.saveNote(block)` | `lib/core/note/persistence/note_repository.dart:201` |
| 列出所有笔记 | `NoteRepository.listAllNotes()` | `lib/core/note/persistence/note_repository.dart:91` |
| 老 .json → .toml 迁移 | `NoteMigration.migrateIfNeeded(dir)` | `lib/core/note/persistence/note_migration.dart` |

---

## 13. 测试覆盖建议

| 场景 | 期望 |
|---|---|
| 完整笔记 roundtrip | encode → TOML → decode → Block，等价 |
| `id` 缺失 TOML | decode 后 Block 有 fallback uuid |
| 未知 `type` TOML | 当前：抛 `ArgumentError`；目标：fallback paragraph |
| 空 spans = `[]` | 等价于空 RichText |
| 空 spans = `[[]]` 头 | 兼容 |
| `level: '1'`（字符串） | 当前：TypeError；目标：解析为 1 |
| 嵌套 5 层 children | 正常解析 |
| 根 block content 缺失 | fallback `RichText.empty()` |
| `properties` 表缺失 | fallback `{}` |

---

## 14. 版本历史

| 日期 | 改动 | 触发 |
|---|---|---|
| 2026-06-17 | 从 JSON 切换到 TOML | 接入后端 agent |
| 2026-06-18 | `BlockCodec.decode` 在 `id` 缺失时 fallback uuid | 后端 LLM 删除根 block id 行 |
| 2026-06-18 | `decodeToml` 加错误日志 | 排查解析失败 |
| 2026-06-18 | `articleEndpoint` 字段名 `baseUrl` → `baseURL` | 修正与后端 swagger 不一致 |
| 2026-06-18 | 建立本文档 | 规范化协议 |
