# 数据模型层

来源：`lib/core/note/core/`

## 目录结构

```
core/
├── core.dart                     # barrel (export models + text + identity)
├── models/
│   ├── models.dart               # barrel
│   ├── block.dart                # Block
│   ├── block_data.dart           # BlockData
│   ├── block_type.dart           # BlockType (19种)
│   └── flat_block.dart           # FlatBlock
├── text/
│   ├── text.dart                 # barrel
│   ├── rich_text.dart            # RichText
│   ├── span.dart                 # Span
│   └── inline_format.dart        # InlineFormat (sealed class)
└── identity/
    ├── identity.dart             # barrel
    ├── block_id.dart             # BlockId (UUID v4)
    └── block_path.dart           # BlockPath
```

## Block — 文档树的原子单位

```dart
class Block {
  final String id;                              // UUID v4，全局唯一
  final BlockType type;                         // 类型枚举（19种）
  final RichText content;                       // 富文本内容
  final List<Block> children;                   // 子块（仅序列化时携带）
  final BlockData data;                         // 类型专属元数据
  final Map<String, dynamic> properties;        // 通用扩展属性
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

**关键约束：**
- 同一性由 `id` 决定（`==` / `hashCode`）
- `copyWith` 实现不可变更新
- `children` 运行时由外部管理，仅序列化时嵌套
- JSON 序列化/反序列化完整（`toJson` / `fromJson`）

## BlockType — 19 种类型枚举

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
| columnList | — | ✓ | — |
| column | — | ✓ | ratio: double |
| syncedBlock | — | — | refBlockId: string |

`fromTag(tag)` 中未知 tag 默认 fallback 为 `paragraph`。

## RichText — 富文本

```dart
class RichText {
  final List<Span> spans;

  factory RichText.text(String text);     // 纯文本 → 单个 Span
  factory RichText.empty();               // []
  String toPlainText();                   // 纯文本拼接
  int get length;                         // 纯文本长度
  bool get isEmpty;
  RichText copyWith({List<Span>? spans});
}
```

## Span — 文本片段

```dart
class Span {
  final String text;
  final InlineFormat? format;

  const Span.text(this.text) : format = null;
  bool get isPlain;
  Span copyWith({String? text, InlineFormat? format});
}
```

## InlineFormat — 内联格式（sealed class）

| 子类 | 字段 | JSON type |
|------|------|-----------|
| BoldFormat | — | bold |
| ItalicFormat | — | italic |
| InlineCodeFormat | — | inline_code |
| StrikethroughFormat | — | strikethrough |
| LinkFormat | url | link |
| MentionFormat | blockId | mention |
| ColorFormat | color | color |

每个 Span 最多一种格式，复合格式拆为相邻 Span。`fromJson` 未知类型 → BoldFormat。

## BlockData — 类型专属数据

```dart
class BlockData {
  T? get<T>(String key);
  T getOrDefault<T>(String key, T defaultValue);
  BlockData merge(Map<String, dynamic> updates);
  bool validate(BlockType type);       // 校验 data schema
}
```

各类型 data schema 见 BlockType 表。

## BlockId — UUID v4

```dart
class BlockId {
  static String generate();   // xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
}
```

纯 Dart 实现，无外部依赖。

## BlockPath — 树路径寻址

```dart
class BlockPath {
  final List<String> ids;               // 根到目标块 ID 序列
  String get last;
  BlockPath append(String id);
  BlockPath removeLast();               // 至少保留一个
  factory BlockPath.fromString(String path);
  static const root = BlockPath(['__root__']);
}
```

## FlatBlock — 扁平化树节点

```dart
class FlatBlock {
  final Block block;
  final int depth;         // 树中深度
  final String parentId;   // 父块 ID
}
```
