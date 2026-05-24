# 持久化层

来源：`lib/core/note/persistence/note_repository.dart`

## 存储结构

- 笔记存储于 `docDir/notes/*.json`
- 每篇笔记一个 JSON 文件，以 `block.id.json` 命名
- JSON 为 page 类型 Block 嵌套序列化

## NoteRepository CRUD

| 方法 | 说明 |
|------|------|
| `listAllNotes()` | 列出所有笔记元数据 `List<NoteInfo>`，按修改时间降序 |
| `getSummary()` | 返回 `NoteSummary`（总数/总块数/总大小） |
| `readNote(String id)` | 读取并解析为根 `Block?` |
| `saveNote(Block block)` | 将根 block 序列化为 JSON 文件 |
| `deleteNote(String id)` | 删除 `{id}.json` |
| `createNote(String title)` | 创建新 page block（不写入磁盘） |
| `readRawContent(String filePath)` | 读取原始 JSON 字符串 |

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

## 标题提取 fallback 逻辑

在 `_extractTitle(Block block)` 中：

1. 根 block 是 page 类型 → 取 content 纯文本
2. 递归查找第一个 heading 子块 → 取其文本
3. 根 content 前 40 字符（超长截断 + "…"）
4. fallback → "未命名笔记"
