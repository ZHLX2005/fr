# 基本结构体类型

## Block — 文档树的原子单位

```dart
class Block {
  final String id;                              // UUID v4，全局唯一
  final BlockType type;                         // 类型枚举（16种）
  final RichText content;                       // 富文本内容（Span序列）
  final List<Block> children;                   // 子块（仅序列化使用）
  final BlockData data;                         // 类型专属元数据
  final Map<String, dynamic> properties;        // 通用扩展属性
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

**关键约束：**
- `type.canHaveChildren == false` 时，`children` 必须为空
- `type.containerOnly == true` 时，`content` 必须为空
- 同一性由 `id` 决定（`==` / `hashCode` 基于 id）
- 通过 `copyWith` 实现不可变更新

## BlockType — 块类型枚举（16种）

```dart
enum BlockType {
  page('page',            containerOnly: true,  canHaveChildren: true),
  paragraph('paragraph'),
  heading('heading'),                           // data: {level: 1-6}
  todo('todo'),                                 // data: {checked: bool}
  toggle('toggle',        canHaveChildren: true),
  bulletListItem('bullet_list_item', canHaveChildren: true),
  orderedListItem('ordered_list_item', canHaveChildren: true), // data: {number: int}
  quote('quote'),
  code('code'),                                 // data: {language: string}
  divider('divider',      containerOnly: true),
  callout('callout'),                           // data: {icon: string}
  image('image'),                               // data: {src, caption, width, height}
  embedCard('embed_card'),                      // data: {title, subtitle, icon, sourceBlockId}
  bookmark('bookmark'),                         // data: {url, title, description, favicon}
  equation('equation'),                         // data: {latex: string}
  database('database',    canHaveChildren: true),
  columnList('column_list', canHaveChildren: true),
  column('column',        canHaveChildren: true), // data: {ratio: double}
  syncedBlock('synced_block'),                  // data: {refBlockId: string}

  const BlockType(this.tag, {this.containerOnly = false, this.canHaveChildren = false});
}
```

**两个标志位：**
- `containerOnly` — 只能作为容器，不能有文字内容（page, divider）
- `canHaveChildren` — 可以包含子块（page, toggle, list items, columnList/column, database）

## RichText — 富文本内容

```dart
class RichText {
  final List<Span> spans;  // Span 序列

  factory RichText.text(String text);   // 从纯文本创建（单个无格式Span）
  factory RichText.empty();             // 空内容 []
  String toPlainText();                 // 纯文本拼接（搜索索引用）
}
```

**核心规则：** RichText 不可变。修改需构造新实例。

## Span — 文本片段

```dart
class Span {
  final String text;          // 文本内容
  final InlineFormat? format; // 可选的格式

  const Span.text(this.text) : format = null;  // 无格式构造
}
```

## InlineFormat — 内联格式（sealed class）

```dart
sealed class InlineFormat {
  // BoldFormat        — 粗体
  // ItalicFormat      — 斜体
  // InlineCodeFormat  — 行内代码
  // StrikethroughFormat — 删除线
  // LinkFormat(url)   — 链接
  // MentionFormat(blockId) — 提及块
  // ColorFormat(color) — 文字颜色
}
```

**关键约束：** 每个 Span 最多一个格式。需要多重格式（如粗体+斜体）时，将文本拆为多个相邻 Span。

## BlockData — 类型专属数据

```dart
class BlockData {
  // 内部为 Map<String, dynamic>
  T? get<T>(String key);                    // 安全取值
  T getOrDefault<T>(String key, T default); // 带默认值
  BlockData merge(Map<String, dynamic>);    // 合并更新
  bool validate(BlockType type);            // 按类型校验 schema

  factory BlockData.fromMap(Map<String, dynamic> data);
  factory BlockData.empty();                // {}
}
```

**各类型 data schema：**

| BlockType | 字段 | 类型 | 约束 |
|-----------|------|------|------|
| heading | level | int | 1-6 |
| todo | checked | bool | — |
| code | language | string | — |
| image | src | string | 必填 |
| image | caption | string | — |
| image | width, height | num | — |
| embedCard | title, subtitle, icon, sourceBlockId | string | — |
| bookmark | url, title, description, favicon | string | — |
| equation | latex | string | — |
| column | ratio | num | — |
| orderedListItem | number | int | — |
| callout | icon | string | — |

## BlockId — UUID v4 生成器

```dart
class BlockId {
  static String generate();  // 返回 UUID v4 格式：xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
}
```

- 无外部依赖，最小化实现
- 利用微秒时间戳 + 计数器保证唯一性
- 多人协作场景下保证 ID 不冲突

## BlockPath — 树路径寻址

```dart
class BlockPath {
  final List<String> ids;       // 从根到目标块的 ID 路径

  String get last;              // 路径末尾 ID
  BlockPath append(String id);  // 追加路径
  BlockPath removeLast();       // 返回上一级
  String toString();            // "id1/id2/id3"
  factory BlockPath.fromString(String path); // 反序列化
  static const root;            // ['__root__']
}
```

**用途：** UI 导航恢复、AI Context Builder 路径描述。

## FlatBlock — 扁平化块（AI Context 用）

```dart
class FlatBlock {
  final Block block;       // 块本身
  final int depth;         // 在树中的深度
  final String parentId;   // 父块 ID
}
```

**用途：** `BlockTree.flattenSince(id)` 将子树扁平展开为 `List<FlatBlock>`，附带缩进深度信息供 AI 理解文档结构。

## TreeChange — 树变更描述（sealed class）

```dart
sealed class TreeChange {
  final String parentId;
  final String blockId;
}

class InsertedChange extends TreeChange;  // 新增块
class RemovedChange extends TreeChange;   // 删除块
class UpdatedChange extends TreeChange {  // 更新块（含旧值）
  final Map<String, dynamic>? oldValues;
}
class MovedChange extends TreeChange {    // 移动块
  final String oldParentId;
}
```

**用途：** 通过 `Stream<List<TreeChange>>` 推送增量变更，UI 层按变更类型高效更新。

## BlockOp — 可逆操作命令（sealed class）

```dart
sealed class BlockOp {
  BlockOp apply(BlockTree tree);  // 执行 → 返回逆操作
  BlockOp get reverse;            // 直接获取逆操作（不执行）
  String get opType;              // 操作类型标签
}

// 具体操作类型：
class InsertBlock extends BlockOp {   // 插入块
  final Block block;
  final String parentId;
  final String? afterId;
}

class UpdateBlock extends BlockOp {   // 更新块
  final String id;
  final RichText? content;
  final BlockType? type;
  final BlockData? data;
  final Map<String, dynamic>? properties;
}

class DeleteBlock extends BlockOp {   // 删除块
  final String id;
}

class MoveBlock extends BlockOp {     // 移动块
  final String id;
  final String newParentId;
  final String? afterId;
}

class MergeBlocks extends BlockOp {   // 合并两个块
  final String sourceId;
  final String targetId;
}

class SplitBlock extends BlockOp {    // 分割一个块
  final String id;
  final int splitOffset;
  final Block? removedBlock;          // 仅用于 reverse
}

class NopOp extends BlockOp;          // 空操作
```

**逆操作对偶表：**

| 操作 | apply 返回的逆操作 |
|------|-------------------|
| InsertBlock(block, parentId, afterId) | DeleteBlock(block.id) |
| UpdateBlock(id, ...new) | UpdateBlock(id, ...old) |
| DeleteBlock(id) | InsertBlock(savedBlock, parentId) |
| MoveBlock(id, newParent) | MoveBlock(id, oldParent, oldAfterId) |
| MergeBlocks(source, target) | SplitBlock(target, offset, removedBlock) |
| SplitBlock(id, offset) | MergeBlocks(newId, id) |
| NopOp | NopOp |

## ValidationError — 验证错误

```dart
class ValidationError {
  final String message;
}
```

- 由 `OpValidator.validate(ops)` 返回
- 多个错误可同时返回，调用方自行聚合展示

## BlockSelection — 编辑器选区状态

```dart
class BlockSelection {
  final String blockId;
  final int cursorOffset;  // 光标偏移
}
```

- 由 `BlockEditorController` 管理
- 决定插入、删除、格式修改等操作的作用目标

## AiActionResult — AI 操作结果

```dart
class AiActionResult {
  final List<BlockOp> appliedOps;   // 已执行的操作
  final List<ValidationError> errors; // 验证错误
  final String summary;              // 操作摘要

  bool get success;     // errors.isEmpty
  bool get hasChanges;  // appliedOps.isNotEmpty
}
```

- `AiAgent.processToolCalls()` 的返回值
- 调用方根据 `success` / `hasChanges` 决定 UI 反馈

## _HistoryEntry — 历史记录条目（内部类）

```dart
class _HistoryEntry {
  final List<BlockOp> ops;       // 原始操作
  final List<BlockOp> reverses;  // 逆操作（用于撤销）
}
```

- 由 `OperationHistory` 内部管理
- `maxHistory = 200`，超限丢弃最早
- `mergeWindowMs = 300ms`：同一块连续 UpdateBlock 自动合并
