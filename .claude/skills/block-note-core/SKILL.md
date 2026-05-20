---
name: block-note-core
description: |
  当用户询问块编辑器、BlockTree、结构化笔记、Notion-like编辑器、
  笔记核心架构、块操作（BlockOp）、富文本Span、操作历史/撤销重做、
  AI集成编辑、Markdown导入导出时触发。
---

# Block Note Core — 结构化块树笔记编辑器核心架构

基于 `lib/core/note/` 的结构化笔记编辑器，以 **BlockTree（块树）** 为核心，
涵盖数据结构、操作原语、历史栈、验证层、富文本、AI集成、Markdown桥接等。

## 核心架构图

```
BlockEditorController (状态管理)
  ├── BlockTree (双索引树结构)
  │     ├── id → Block
  │     ├── id → parentId
  │     └── parentId → [childId]
  ├── OperationHistory (undo/redo 历史栈)
  ├── OpValidator (AI 操作验证)
  └── AiAgent (自然语言→操作)
```

## 1. Block 数据模型

文件: `blocks/block.dart`

- **Block** 是文档树的原子单位，包含：id、type、content（RichText）、children、data（类型专属元数据）、properties
- 不可变风格：`copyWith` 创建新实例
- JSON 序列化/反序列化完整
- 注意：Block 的 `children` 在运行时通过 `_childrenOf` 索引管理，`BlockTree.fromJson` 重建时从嵌套 JSON 重建索引

```dart
class Block {
  final String id;
  final BlockType type;
  final RichText content;     // 富文本内容
  final List<Block> children; // 子块（仅在序列化时使用）
  final BlockData data;       // 类型专属数据
  final Map<String, dynamic> properties;
}
```

## 2. BlockType — 16 种类型枚举

文件: `blocks/block_type.dart`

每种类型定义了 `containerOnly` 和 `canHaveChildren` 标志：

| 类型 | containerOnly | canHaveChildren | data 字段 |
|------|:---:|:---:|------|
| page | ✓ | ✓ | — |
| paragraph | — | — | — |
| heading | — | — | level: 1-6 |
| todo | — | — | checked: bool |
| toggle | — | ✓ | — |
| bulletListItem | — | ✓ | — |
| orderedListItem | — | ✓ | number: int |
| quote | — | — | — |
| code | — | — | language: string |
| divider | ✓ | — | — |
| callout | — | — | icon: string |
| image | — | — | src, caption, width, height |
| embedCard | — | — | title, subtitle, icon, sourceBlockId |
| bookmark | — | — | url, title, description, favicon |
| equation | — | — | latex: string |
| database | — | ✓ | 子 Page 作为行 |
| columnList/column | — | ✓ | ratio: double（column） |
| syncedBlock | — | — | refBlockId: string |

## 3. RichText & Span & InlineFormat

文件: `blocks/rich_text.dart`

- **RichText** = `List<Span>` 的序列
- **Span** = `text` + `InlineFormat?`
- **InlineFormat** — sealed class 层次：
  - `BoldFormat`, `ItalicFormat`, `InlineCodeFormat`, `StrikethroughFormat`
  - `LinkFormat(url)`, `MentionFormat(blockId)`, `ColorFormat(color)`
- **BlockData** — 类型安全的数据访问，支持 `validate(BlockType)` 按类型校验 schema

```dart
class RichText { final List<Span> spans; }
class Span { final String text; final InlineFormat? format; }
```

## 4. BlockTree — 双索引树结构

文件: `blocks/block_tree.dart`

- **双索引**：`_blocks`(id→Block) + `_parents`(id→parentId) + `_childrenOf`(parentId→childId)
- 隐藏根节点 `__root__`，所有块挂在根下
- **变更流**：`StreamController<List<TreeChange>>` 推送增量变更通知 UI

### 核心方法

| 方法 | 说明 |
|------|------|
| get(id) | O(1) 查询块 |
| parentOf(id) | O(1) 查询父块 |
| childIdsOf(id) | O(1) 查询子块 ID 列表 |
| depthOf(id) | 计算块深度（回溯到根） |
| pathToRoot(id) | 从块到根的路径 |
| flattenSince(id, windowSize) | 扁平展开子树（用于 AI Context） |
| insert(block, parentId, afterId) | 插入块，断言完善 |
| update(id, content/type/data/properties) | 部分更新 |
| remove(id) | 递归删除子树 |
| move(id, newParentId, afterId) | 移动块（含循环检测） |
| clear() | 清空（保留根节点） |

### TreeChange sealed class

四种变更类型，用于 UI 增量更新：

```dart
sealed class TreeChange {
  final String parentId;
  final String blockId;
}
class InsertedChange extends TreeChange { ... }
class RemovedChange extends TreeChange { ... }
class UpdatedChange extends TreeChange { ... }
class MovedChange extends TreeChange { ... }
```

## 5. BlockOp — 可逆操作命令模式

文件: `blocks/block_op.dart`

**核心思想**：每个操作可执行并返回逆操作，实现"操作即数据"的 Event Sourcing。

```dart
sealed class BlockOp {
  BlockOp apply(BlockTree tree);   // 执行 → 返回逆操作
  BlockOp get reverse;             // 直接获取逆操作（不执行）
}
```

### 操作类型

| 操作 | 构造参数 | apply 返回的逆操作 |
|------|---------|-------------------|
| InsertBlock(block, parentId, afterId) | 要插入的块 + 位置 | DeleteBlock(block.id) |
| UpdateBlock(id, content/type/data/properties) | 块 ID + 要更新的字段 | UpdateBlock(id, 旧值...) |
| DeleteBlock(id) | 块 ID | InsertBlock(block, parentId) |
| MoveBlock(id, newParentId, afterId) | 块 ID + 目标位置 | MoveBlock(id, 原位置...) |
| MergeBlocks(sourceId, targetId) | 合并到目标 | SplitBlock(targetId, offset) |
| SplitBlock(id, splitOffset) | 在 offset 处分割 | MergeBlocks(newId, id) |
| NopOp | — | 自身 |

### 分割/合并的 Span 处理

`SplitBlock._splitSpans()` 精确处理跨分割点的 Span：
- 遍历所有 Span，累加字符偏移
- 在分割点处截断跨越的 Span
- 前半段保留在原块，后半段放入新块

## 6. OperationHistory — 事件溯源历史栈

文件: `blocks/op_history.dart`

- **undo 栈** + **redo 栈**，每项包含 `(ops, reverses)`
- **最大 200 条**，超过时丢弃最早的
- **合并窗口 300ms**：相邻的同一块 UpdateBlock 自动合并（避免打字过程中产生大量历史记录）
- `apply(List<BlockOp>)` 批量执行并记录
- `applySingle(BlockOp)` 带合并判断的单次操作
- `undo()` / `redo()` 完整的事务性撤销/重做（执行时再次获取逆操作）

## 7. OpValidator — AI 操作验证层

文件: `blocks/op_validator.dart`

在 apply 前拦截非法操作，**尤其对 AI 生成的操作至关重要**：

| 验证项 | 说明 |
|--------|------|
| 根节点保护 | 不能删除/插入根节点 |
| ID 唯一性 | 不能插入已存在的块 ID |
| 父块存在性 | parentId / afterId 必须在树中 |
| 父子关系一致性 | afterId 必须在指定父块下 |
| 内容约束 | containerOnly 类型不能有文字 |
| 子块约束 | 不支持子块的类型不能有 children |
| data schema | data 与 BlockType 匹配 |
| 循环检测 | 移动不能产生循环引用 |
| 分割越界 | splitOffset 必须在 [1, len-1] 范围 |

## 8. BlockEditorController — 编辑器状态管理

文件: `blocks/block_editor_controller.dart`

连接 BlockTree + OperationHistory + OpValidator + AI 的门面：

- **Selection 管理**：`selectBlock()` / `clearSelection()`
- **UI 操作**：insertBlockAfter / updateContent / toggleType / setHeader / deleteBlock / moveBlock
- **快捷键支持**：toggleBold 等
- **AI 集成**：`applyAiOps()` 验证并执行 AI 操作
- **变更监听**：通过 `ChangeNotifier` + BlockTree 的 Stream 联动 UI

## 9. AiAgent — 自然语言→操作

文件: `blocks/ai/ai_agent.dart`

两种模式：

1. **Tool Use 模式**：`processToolCalls()` 处理 LLM 返回的工具调用结果
   - 工具名 → BlockOp 映射：`insert_block`、`update_block`、`delete_block`、`move_block`、`merge_blocks`、`split_block`
   - 验证 → 执行 → 返回总结

2. **模拟 AI 模式**：`simulateCommand()` 规则解析中文/英文指令
   - 支持：插入标题/待办/段落、删除、设置标题、总结
   - 用于开发和测试阶段

### ContextBuilder

- `build()` 构建 AI 上下文（扁平块树 + 元信息）
- `buildFullText()` 导出纯文本

## 10. MarkdownBridge — 双向转换

文件: `bridges/markdown_bridge.dart`

**导出**：`exportToMarkdown(BlockTree)` — 递归遍历树，按类型渲染：
- heading → `## ` + 文本
- bulletListItem → `- ` 
- todo → `- [x] ` / `- [ ] `
- code → ```lang + 代码 + ```
- quote → `> ` 每行
- callout → `> [!NOTE/WARNING/DANGER]`
- image/bookmark → markdown 链接语法

**导入**：`parseMarkdown(String)` — 逐行解析为 `List<Block>`
- 识别 heading、代码块、分割线、todo、无序/有序列表、引用、段落
- 高级格式（表格、嵌套列表）暂不支持

## 11. 序列化

文件: `blocks/block_persistence.dart`

- `BlockTreeSerializer.toJson(tree)` → 嵌套 JSON 字符串
- `BlockTreeSerializer.fromJson(json)` → 从 JSON 重建树（含索引重建）
- `BlockSerializer.compact(block)` → 不含子块的紧凑序列化（用于引用）

## 错误案例

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| 运行时使用 Block.children 遍历 | 遍历到的 children 可能为空（索引在 _childrenOf 中） | 使用 `tree.childrenOf(id)` 或 `tree.childIdsOf(id)` |
| 直接修改 _blocks 内部索引 | 破坏双索引一致性 | 必须通过 BlockTree.insert/update/remove API |
| 绕过 OpValidator 执行 AI 操作 | AI 可能产生循环引用、删除根节点等破坏性修改 | 始终通过 `editor.applyAiOps(ops)` 执行 |
| 忘记调用 history.apply 直接修改 tree | 无法撤销 | 所有修改必须通过 OperationHistory 提交 |
| UpdateBlock 不校验 block 是否存在 | 空操作或 NopOp，无反馈 | 使用 OpValidator 前置验证 |
| SplitBlock 分割点包含 Span 中间 | 格式错乱 | 正确实现见 `_splitSpans()` 的跨越分割处理 |

## 触发场景

- 用户问"块编辑器的核心数据结构" → 讲解 BlockTree 双索引
- 用户问"如何实现撤销重做" → 讲解 OperationHistory + BlockOp 逆操作
- 用户问"AI 怎么编辑文档" → 讲解 AiAgent 的 Tool Use 模式
- 用户问"Markdown 转块" → 讲解 MarkdownBridge.parseMarkdown
- 用户问"富文本格式怎么存储" → 讲解 RichText / Span / InlineFormat
- 用户想添加新的块类型 → 在 BlockType 枚举中添加并实现 data validate
