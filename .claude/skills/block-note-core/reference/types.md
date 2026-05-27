# 数据模型层

来源：`lib/core/note/core/`

## 核心架构

```
sealed class BlockType     ← 19 个 part 子类
       ↓
Block { id, type, content, children, properties }
  type: BlockType (sealed)   ← 取代旧版 BlockType enum + BlockData
  content: RichText?         ← List<Span>
  children: List<Block>?     ← 运行时外部管理，仅序列化时嵌套
```

**设计原则：**
- 类型安全：`(block.type as HeadingType).level` 不再是 `dynamic`
- 单一职责：每种类型的数据和序列化逻辑在各自文件
- 可扩展：新增类型 = 新建 1 个 part 文件 + type.dart 的 fromJson 加 1 行
- 穷举检查：sealed class 保持 switch exhaustive

---

## Block — 文档树的原子单位

`lib/core/note/core/block.dart`

```dart
class Block {
  final String id;
  final BlockType type;         // sealed class
  final RichText? content;
  final List<Block>? children;
  final Map<String, dynamic>? properties;

  Block({required this.id, required this.type, ...});
  Block copyWith({...});
  Map<String, dynamic> toJson();
  factory Block.fromJson(Map<String, dynamic> json);
}
```

**关键约束：**
- 同一性由 `id` 决定（`==` / `hashCode`）
- `copyWith` 实现不可变更新
- `children` 运行时由外部管理（EditorState._blocks 扁平存储），仅序列化时嵌套

---

## BlockType — sealed class 继承体系

`lib/core/note/core/type/type.dart`（基类）+ 19 个 `part of 'type.dart'` 子类。

### 基类定义

```dart
sealed class BlockType {
  const BlockType({
    required this.tag,
    this.containerOnly = false,
    this.canHaveChildren = false,
  });

  final String tag;
  final bool containerOnly;       // true = 不可编辑、仅渲染
  final bool canHaveChildren;     // true = 可包含子块

  // 各子类必须实现的序列化
  Map<String, dynamic> toJson();
  factory BlockType.fromJson(Map<String, dynamic> json);  // 按 tag 分派

  // 子类可覆写的行为
  BlockType? get onEnterType => const ParagraphType();  // Enter 创建的块类型
  bool get multiline => false;   // true = 块内可换行（如 CodeType）
}
```

### 所有子类一览

| 文件 | 类名 | tag | containerOnly | canHaveChildren | 额外字段 |
|------|------|:---:|:---:|:---:|------|
| `page.dart` | `PageType` | page | ✓ | ✓ | — |
| `paragraph.dart` | `ParagraphType` | paragraph | — | — | — |
| `heading.dart` | `HeadingType` | heading | — | — | `level: int` |
| `todo.dart` | `TodoType` | todo | — | — | `checked: bool` |
| `toggle.dart` | `ToggleType` | toggle | — | ✓ | — |
| `bullet_list_item.dart` | `BulletListItemType` | bullet_list_item | — | ✓ | — |
| `ordered_list_item.dart` | `OrderedListItemType` | ordered_list_item | — | ✓ | `number: int` |
| `quote.dart` | `QuoteType` | quote | — | — | — |
| `code.dart` | `CodeType` | code | — | — | `language: String` |
| `divider.dart` | `DividerType` | divider | ✓ | — | — |
| `callout.dart` | `CalloutType` | callout | — | — | `icon: String` |
| `image.dart` | `ImageType` | image | ✓ | — | `src, caption, width, height` |
| `embed_card.dart` | `EmbedCardType` | embed_card | — | — | `title, subtitle, icon, sourceBlockId` |
| `bookmark.dart` | `BookmarkType` | bookmark | — | — | `url, title, description, favicon` |
| `equation.dart` | `EquationType` | equation | — | — | `latex: String` |
| `database.dart` | `DatabaseType` | database | — | ✓ | — |
| `column_list.dart` | `ColumnListType` | column_list | — | ✓ | — |
| `column.dart` | `ColumnType` | column | — | ✓ | `ratio: double` |
| `synced_block.dart` | `SyncedBlockType` | synced_block | — | — | `refBlockId: String` |

### 子类格式（示例：heading.dart）

```dart
part of 'type.dart';

class HeadingType extends BlockType {
  final int level;

  const HeadingType({this.level = 1}) : super(tag: 'heading');

  factory HeadingType.fromData(Map<String, dynamic> data) =>
      HeadingType(level: data['level'] as int? ?? 1);

  @override
  Map<String, dynamic> toJson() => {'level': level};

  @override
  bool operator ==(Object other) =>
      other is HeadingType && other.level == level;

  @override
  int get hashCode => Object.hash(runtimeType, level);

  // 覆写 Enter 行为 — heading 按 Enter 创建新段落
  @override
  BlockType? get onEnterType => const ParagraphType();
}
```

### Enter 行为策略

各类型可覆写 `onEnterType` 和 `multiline`：

| 类型 | onEnterType | multiline |
|------|:-----------:|:---------:|
| 基类默认 | `ParagraphType` | `false` |
| CodeType | `null`（留在本块） | `true` |
| TodoType | `TodoType(checked: false)` | `false` |
| OrderedListItemType | `OrderedListItemType(number: number+1)` | `false` |
| DividerType/Page等 | `null` | `false` |

`onEnterType = null` 表示 Enter 无操作（编辑态由 onSubmitted 控制不创建新块）。

### 输入类型转换

各类型可定义 `static inputTrigger`，当用户在空段落输入匹配前缀时自动转换。

```dart
// divider.dart
static TypeConversionRule<BlockType> get inputTrigger => TypeConversionRule(
  pattern: RegExp(r'^---$'),
  createType: (_) => const DividerType(),
  clearContent: true,
);

// ordered_list_item.dart
static TypeConversionRule<BlockType> get inputTrigger => TypeConversionRule(
  pattern: RegExp(r'^(\d+)\. '),
  createType: (m) => OrderedListItemType(number: int.parse(m.group(1)!)),
);
```

| 类型 | 触发输入 | clearContent |
|------|----------|:-----------:|
| DividerType | `---` | ✓ |
| CodeType | `` ``` `` / `` ```dart `` | ✓ |
| HeadingType | `# ` / `## ` / `### ` | — |
| BulletListItemType | `- ` / `* ` | — |
| OrderedListItemType | `1. ` | — |
| TodoType | `[ ] ` / `[x] ` | — |
| QuoteType | `> ` | — |

规则由 `TypeConversionRegistry.createDefault()` 收集（`type_conversion_registry.dart`），`NoteFactory.tryConvert()` 对外暴露。触发时消耗前缀，剩余文本保留为 content。

---

## RichText — 富文本

`lib/core/note/core/text/rich_text.dart`

```dart
class RichText {
  final List<Span> spans;

  factory RichText.text(String text);    // 纯文本 → 单个 Span
  factory RichText.empty();              // []
  String toPlainText();
  int get length;
  bool get isEmpty;
  RichText copyWith({List<Span>? spans});
  Map<String, dynamic> toJson();
  factory RichText.fromJson(Map<String, dynamic> json);
}
```

## Span — 文本片段

`lib/core/note/core/text/span.dart`

```dart
class Span {
  final String text;
  final InlineFormat? format;

  const Span.text(this.text) : format = null;
  bool get isPlain;
  Span copyWith({String? text, InlineFormat? format});
  Map<String, dynamic> toJson();
  factory Span.fromJson(Map<String, dynamic> json);
}
```

## InlineFormat — 内联格式（sealed class）

`lib/core/note/core/text/inline_format.dart`

| 子类 | 字段 | JSON type |
|------|------|-----------|
| `BoldFormat` | — | bold |
| `ItalicFormat` | — | italic |
| `InlineCodeFormat` | — | inline_code |
| `StrikethroughFormat` | — | strikethrough |
| `LinkFormat` | url | link |
| `MentionFormat` | blockId | mention |
| `ColorFormat` | color | color |

每个 Span 最多一种格式，复合格式拆为相邻 Span。未知类型 → BoldFormat。

### 注册模式

```dart
// 新格式注册到 InlineFormatRegistrar
class InlineFormatRegistrar {
  Map<String, InlineFormat Function(Map<String, dynamic>)> createFactories() => {
    'bold': (_) => const BoldFormat(),
    'italic': (_) => const ItalicFormat(),
    // 新增： 'underline': (_) => const UnderlineFormat(),
  };
}
```

### 新增 InlineFormat 步骤

1. 在 `inline_format.dart` 中新增 sealed 子类
2. 实现 `toJson()`，返回唯一 JSON type 字符串
3. 在 `InlineFormatRegistrar.createFactories()` 注册工厂
4. （可选）在 `InlineFormatCodec` 中添加 encode/decode 逻辑

---

## 编解码体系

```
BlockCodec
  ├── BlockTypeRegistry   (tag → 子类工厂)
  └── RichTextCodec
       └── InlineFormatRegistry (JSON type → 格式工厂)
```

- `Block.toJson()` → `{id, type, content, children, properties}`
- `Block.fromJson()` → `BlockTypeRegistry.resolve(tag, data)` + `RichTextCodec`

---

## Identity

`lib/core/note/core/identity/`

```dart
class BlockIdentityFactory {
  const BlockIdentityFactory();
  static String generateId() => BlockId.generate();    // UUID v4
  static BlockPath path(List<String> ids) => BlockPath(ids);
}
```

统一入口，底层可随时替换（UUID v4 → 平台 UUID）。

---

## 新增 BlockType 完整步骤

1. 在 `lib/core/note/core/type/` 新建 `your_type.dart` 作为 `part of 'type.dart'`
2. 在 `type.dart` 中添加 `part 'your_type.dart';`
3. 定义子类（继承 BlockType，实现 toJson/fromData/==/hashCode）
4. （可选）覆写 `onEnterType`、`multiline`
5. （可选）添加 `static inputTrigger` 实现输入转换
6. 在 `type_registry.dart` 的 `BlockTypeRegistrar.createFactories()` 注册反序列化工厂
7. 在 `widget/strategies/` 新建渲染策略（见 demo-ui.md）
8. 在 `BlockWidgetBuilder` 或 `BlockTypeRegistrar.widgetFactories` 注册策略
