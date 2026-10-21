# 持久化层

来源：`lib/core/note/persistence/note_repository.dart`

## 存储结构

- 笔记存储于 `getApplicationDocumentsDirectory()/notes/{id}.json`
- 每篇笔记一个 JSON 文件，以根 block 的 `id.json` 命名
- JSON 为 page 类型 Block 嵌套序列化（`Block.toJson()` / `fromJson()`）

## NoteRepository CRUD

```dart
class NoteRepository {
  NoteRepository(BlockCodec codec);
  Future<List<NoteInfo>> listAllNotes();    // dir.listSync() + tryParse
  Future<NoteSummary> getSummary();
  Future<Block?> readNote(String id);
  Future<void> saveNote(Block root);
  Future<void> deleteNote(String id);
  Future<String> readRawContent(String filePath);
}
```

| 方法 | 说明 |
|------|------|
| `listAllNotes()` | 列出所有笔记元数据，按修改时间降序。使用 `dir.listSync()`（非 `dir.list()` 流）避免 Windows 流挂起 |
| `getSummary()` | 返回 `NoteSummary`（总数/总块数/总大小） |
| `readNote(id)` | 读取并解析为根 `Block?` |
| `saveNote(block)` | 将根 block 序列化为 `{id}.json` |
| `deleteNote(id)` | 删除文件 |
| `readRawContent(path)` | 读取原始 JSON 字符串 |

## 辅助类型

```dart
class NoteInfo {
  final String id;
  final String title;
  final int blockCount;
  final int fileSize;
  final DateTime updatedAt;
  final String fileName;
  final String filePath;
}

class NoteSummary {
  final int noteCount;
  final int totalBlocks;
  final int totalSize;
}
```

## 标题提取逻辑

1. 页面的第一个 `HeadingType` 子块文本
2. 根 block content 前 40 字符（超长截断 + `…`）
3. fallback → `"未命名笔记"`

## NoteFactory — 领域门面

`lib/core/note/factory.dart`

封装所有内部服务，外部通过 `NoteRootScope.of(context).noteRoot` 访问。

```dart
class NoteFactory {
  // 单点构造所有依赖
  static NoteFactory create();

  // 块构造
  Block createBlock(BlockType type, ...);
  String generateId();

  // CRUD
  Future<List<NoteInfo>> listNotes();
  Future<Block?> loadNote(String id);
  Future<void> saveNote(Block root);
  Future<void> deleteNote(String id);

  // 渲染 + 编辑
  Widget renderBlock(Block block, {onToggleTodo, onTapAddImage});
  Widget buildEditor(Block block, {required Widget textField, onToggleTodo});
  TextStyle? textStyleFor(Block block);
  List<BlockTypeInfo> get availableTypes;

  // 序列化
  Map<String, dynamic> serializeBlock(Block block);

  // 解析
  List<Block> parseMarkdown(String source);

  // 输入类型转换
  (BlockType, String)? tryConvert(String text);
}
```

`create()` 内部初始化链：
```
idFactory → typeRegistry → formatRegistry
    → richTextCodec → blockCodec → NoteRepository
    → widgetFactory → BlockRenderer
    → conversionRegistry → NoteFactory._()
```

## NoteRootScope — InheritedWidget DI

`lib/core/note/note_root_scope.dart`

```dart
class NoteRootScope extends InheritedWidget {
  final NoteFactory noteRoot;
  static NoteRootScope of(BuildContext context);
}
```

用法：在 `main()` 创建 `NoteFactory.create()`，包裹应用根节点。

## ⚠️ Windows 注意事项

- `Directory.list()` 流在 Windows 上可能挂起 → 使用 `dir.listSync()`
- 异步操作（`NotePanel._loadNotes`、`_NotePreviewSheet._loadContent`）需要 `addPostFrameCallback` 包裹 `NoteRootScope.of(context)`，因为 `InheritedWidget` 在 `initState()` 时不可用

## 保存竞争防护

`EditorState._save()` 是即发即弃的（从 `onChanged`、`deleteBlock` 等处调用）。删除笔记时需等待待处理保存完成，使用 `_pendingSave` 串联机制：

```dart
Future<void>? _pendingSave;

Future<void> _save() {
  if (_noteId == null) return Future.value();
  final noteId = _noteId!;
  final blocks = List<Block>.of(_blocks);
  _pendingSave = (_pendingSave ?? Future.value()).then((_) =>
    _noteFactory.saveNote(...)
  );
}

Future<void> deleteNote(String id) async {
  await _pendingSave;          // 等待待处理保存
  await _noteFactory.deleteNote(id);
  await _noteFactory.deleteNote(id);  // 再次删除捕获延迟写入
  ...
}
```
