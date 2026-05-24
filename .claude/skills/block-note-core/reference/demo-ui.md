# UI Demo 层

来源：`lib/lab/demos/block_editor_demo/`

## 目录结构

```
lib/lab/demos/block_editor_demo/
├── block_editor_demo.dart    # DemoPage 入口 + 底部 Toolbar
├── state.dart                # EditorState (ChangeNotifier)
├── card.dart                 # BlockCard 块卡片
├── renderer.dart             # 类型专属渲染器
├── note_panel.dart           # 笔记列表侧边栏
└── type_panel.dart           # 类型 + 工具操作面板
```

---

## EditorState — 状态管理

`state.dart`，继承 `ChangeNotifier`。

### 核心状态

```dart
List<Block> _blocks;     // 扁平块列表（运行时父子关系在此维护）
String? _selectedId;     // 选中块 ID
String? _noteId;         // 当前笔记 ID
```

### 方法一览

| 方法 | 触发时机 | 说明 |
|------|---------|------|
| `init()` | 页面启动 | 加载最近笔记或新建空状态 |
| `switchNote(id)` | 切换笔记 | 替换 _blocks |
| `createNewNote()` | 新建 | 清空 + 加一个空段落 |
| `select(id)` | 点击块 | 设置 _selectedId |
| `clearSelection()` | — | 清空选中 |
| `toggleType(newType)` | 类型切换 | 改当前块的 type |
| `deleteBlock()` | 删除按钮 | 删除并选中相邻块 |
| `addBlock()` | 新增 | 尾部加段落块 |
| `addBlockWithType(type, {level})` | 工具栏点击 | 在选中块后插入 |
| `updateContent(id, text)` | 文本输入 | 更新 content |
| `updateImageSrc(id, src)` | 添加图片 | 更新 data.src |
| `toggleTodo(id)` | 复选框 | 切换 checked 状态 |
| `moveBlock(old, new)` | 拖拽排序 | ReorderableListView |
| `importMd(source)` | MD 导入 | 解析 markdown 替换当前笔记 |

**统一模式**：`find → transform(copyWith) → notifyListeners() + _save()`

### 持久化联动

每次变更后调用 `_save()`，将 `_noteId` 作为 page block，`_blocks` 作为其 children，通过 `NoteRepository.saveNote()` 写入。

---

## BlockCard — 块卡片

`card.dart`。

### 结构

```
┌──────────────────────────────────────┐
│ [类型图标] [内容区域........] [✕删除] │
└──────────────────────────────────────┘
```

### 关键逻辑

- **选中与编辑**：点击 → `editorState.select(id)` → `isSelected=true` → 显示 `TextField`
- **非选中态**：显示 `renderBlockContent()` 的静态渲染
- **删除按钮**：仅选中时显示
- **点击图标**：也触发 select，方便小区域点击

### ⚠️ Material 祖先问题

`ReorderableListView` 为每个 item 包裹 `LookupBoundary`，阻断 `TextField` 查找外部 `Material`。
解决方案：BlockCard 根节点包 `Material(type: MaterialType.transparency)`。

### 选中高亮

当前点击不显示整块高亮，直接进入编辑模式。已将 `BoxDecoration` 中的 color/border 移除。

---

## Renderer — 类型渲染器

`renderer.dart`，顶层函数 `renderBlockContent(Block, ...)` 按 `BlockType` switch 分发。

### 已实现类型

| 类型 | 渲染 | 交互 |
|------|------|------|
| page | 标题文本 | — |
| paragraph | 普通文本 | — |
| heading | H1-H3 字号（data.level） | — |
| todo | ☐/☑ + 文本 | 点击复选框 toggleTodo |
| divider | ─── 横线 | — |
| bulletListItem | • 前缀 | — |
| orderedListItem | 1. 2. 3. 前缀 | — |
| quote | 灰色竖线 + 斜体 | — |
| code | 深色背景 + lang 标签 | — |
| callout | 彩色背景 + 图标 | — |
| image | 图片或占位符 | 点击占位符可添加（相册/拍照/URL） |

### 未实现类型

toggle, embedCard, bookmark, equation, database, columnList, column, syncedBlock

---

## Toolbar — 底部工具栏

`block_editor_demo.dart` 中 `_buildBottomToolbar()`。

### 当前按钮

水平滚动条内一行：

**类型插入区**：P / H1 H2 H3 / ☐ / • / 1. / " / <> / — / 💡 / 🖼

**导入 MD**：📄 导入 MD

**展开按钮**：↓ 显示 TypePanel 全部类型

### 添加新工具的三层模板

```
UI                           State                         模型
───────────────────────────────────────────────────────────────
_toolbarButton()         EditorState.doSomething()       Block/RichText...
  onTap → state.xxx()      find → copyWith              copyWith/merge
                            → notifyListeners + _save()
```

#### Step 1: State 层加方法

```dart
// state.dart
void doSomething(String id, /* 工具参数 */) {
  final idx = _blocks.indexWhere((b) => b.id == (id ?? _selectedId));
  if (idx < 0) return;
  final block = _blocks[idx];
  _blocks[idx] = block.copyWith(/* 改 content / type / data */);
  notifyListeners();
  _save();
}
```

#### Step 2: UI 层加按钮

```dart
// block_editor_demo.dart
_toolbarButton(
  label: '工具名',
  icon: Icons.xxx,
  onTap: () => _editorState.doSomething(_editorState.selectedId),
),
```

`_toolbarButton` 通用实现：

```dart
Widget _toolbarButton({
  required String label,
  required IconData icon,
  required VoidCallback onTap,
}) {
  return Padding(
    padding: const EdgeInsets.only(right: 2),
    child: Material(
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Icon(icon, size: 20, color: Colors.grey[600]),
        ),
      ),
    ),
  );
}
```

---

## MD Import — Markdown 导入

### 文件结构

| 文件 | 职责 |
|------|------|
| `lib/core/note/convert/md_to_block.dart` | 纯函数，md 文本 → List<Block> |
| `state.dart` | `importMd()` 方法，解析后替换 _blocks |
| `block_editor_demo.dart` | `_importMdFile()` 文件选取 → 读取 → 导入 |
| `type_panel.dart` | 面板 "工具 → 导入 MD" 磁贴 |

### 调用流程

```
Toolbar (📄) / TypePanel → _importMdFile()
  → MediaService.pickFile(.md)
  → 读取文件内容 (bytes / File)
  → EditorState.importMd(source)
    → MdToBlock.parse(source)
    → 替换 _blocks → notifyListeners → _save()
```

### 支持语法

| Markdown | → BlockType | data |
|----------|-------------|------|
| `# ~ ###### 标题` | heading | level: 1-6 |
| `- 无序列表` | bulletListItem | — |
| `1. 有序列表` | orderedListItem | number: N |
| `- [x] 完成` | todo | checked: true |
| `- [ ] 待办` | todo | checked: false |
| `> 引用` | quote | — |
| `` ```lang `` | code | language: lang |
| `---` | divider | — |
| 其他 | paragraph | — |

内联格式（粗体/斜体/链接）暂存为纯文本。

---

## NotePanel / TypePanel

### NotePanel

`note_panel.dart`，Scaffold endDrawer。
- 显示 NoteRepository.listAllNotes() 列表
- 点击切换笔记
- 新建笔记按钮

### TypePanel

`type_panel.dart`，底部弹出面板（`showModalBottomSheet`）。

结构：
- **标题**：H1 ~ H6
- **列表**：待办 / 无序列表 / 有序列表
- **文本**：段落 / 引用 / 代码 / 提示框
- **媒体**：图片 / 分割线
- **工具**：导入 MD（通过 `onImportMd` 回调，仅在传入时显示）

`_actionTile(context, icon, label, onTap)` — 通用操作磁贴，用于非 BlockType 的操作（如导入 MD），点击后执行回调并关闭面板。

TypePanel 通过 `onImportMd` 回调接收 UI 操作（文件选取），不直接依赖 EditorState 以外的逻辑。

---

## 功能实现状态

| 功能 | 状态 | 位置 |
|------|:----:|------|
| Block 渲染（12种类型） | ✅ | card.dart + renderer.dart |
| BlockType 切换 | ✅ | type_panel.dart |
| 选中编辑 | ✅ | card.dart |
| 删除 | ✅ | card.dart |
| 拖拽排序 | ✅ | ReorderableListView |
| Markdown 导入 | ✅ | md_to_block.dart + state + toolbar + panel |
| 富文本 Span | ❌ | — |
| 格式工具栏 | ❌ | — |
| BlockData 编辑 | ❌ | — |
| 撤销/重做 | ❌ | — |
| Markdown 导出 | ❌ | — |
| AI 集成 | ❌ | — |

## 扩展方向（按优先级）

1. BlockData 属性编辑面板
2. 富文本 Span 编辑器 + 格式工具栏
3. 撤销/重做
4. 补齐未实现 BlockType 渲染器
5. Markdown 导出
