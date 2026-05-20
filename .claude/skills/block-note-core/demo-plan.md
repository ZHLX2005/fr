# Demo Page 实现 Plan

> 目标：基于 `lib/core/note/core/` 的数据结构，生成一个可交互的块编辑器 Demo 页面。
> 原则：每个类型一一映射到 UI 组件，不跳过、不模糊。

---

## I. 类型 → UI 映射总表

| 数据结构 | UI 组件 | 交互功能 |
|---------|---------|---------|
| `BlockTree` | 树形编辑器主面板 | 增删改查、拖拽排序 |
| `Block` | 块卡片（block card） | 选中、编辑、删除、类型切换 |
| `BlockType` (19种) | 类型选择器 + 每种专属渲染器 | 下拉切换类型，实时重渲染 |
| `RichText` / `Span` | 内联文本编辑器 | 输入文字、选中加格式 |
| `InlineFormat` (7种) | 格式工具栏 | 加粗/斜体/代码/划线/链接/提及/颜色 |
| `BlockData` | 属性面板（侧边/弹出） | 按类型显示/编辑 schema 字段 |
| `BlockId` | 显示块 ID（可复制） | 调试信息 |
| `BlockPath` | 面包屑导航 | 显示当前位置路径 |
| `BlockOp` | 操作日志面板 | 记录/回放操作 |
| `OperationHistory` | 撤销/重做按钮 | undo / redo |
| `OpValidator` | 错误提示栏 | 显示验证失败信息 |
| `MarkdownBridge` | 导入/导出按钮 | 粘贴 markdown → 生成块 / 导出为 md |
| `Workspace` / `PageModel` | 页面 Tab 栏 | 多页面切换、新建、删除 |

---

## II. 页面布局

```
┌─────────────────────────────────────────────────────────┐
│  [面包屑 BlockPath]           [+ 新建] [⚙ 类型] [💾 导出] │  ← 顶栏
├────────────────────┬────────────────────────────────────┤
│  页面 Tab 栏       │                                     │
│  [Page 1] [Page 2] │     编辑器主面板                     │
│                    │  ┌─ Block ──────────────────────┐  │
│                    │  │ ⠿ H1  这是标题      [⌄ 类型] │  │
│                    │  │ ───────────────────────────── │  │
│                    │  │ 这是一段普通文字，其中          │  │
│                    │  │ **粗体** *斜体* `代码`        │  │
│                    │  └──────────────────────────────┘  │
│                    │  ┌─ Block ──────────────────────┐  │
│                    │  │ ☐ 待办事项           [⌄ 类型] │  │
│                    │  └──────────────────────────────┘  │
│                    │  ┌─ Block ──────────────────────┐  │
│                    │  │ ─── 分割线                    │  │
│                    │  └──────────────────────────────┘  │
├────────────────────┴────────────────────────────────────┤
│  [B] [I] [Code] [S] [🔗] [@] [🎨]   ← 格式工具栏      │  ← 底栏
│  ↩ 撤销  ↪ 重做   |   操作日志: insert/update/delete... │
└─────────────────────────────────────────────────────────┘
```

---

## III. 各映射详细设计

### 1. Block → 块卡片

```
┌──────────────────────────────────────────┐
│ [拖拽把手] [类型图标] [内容区域] [类型⌄] [✕] │
│                     ↑ RichText 编辑器      │
│                     ↑ 选中时显示光标       │
└──────────────────────────────────────────┘
```

- 每个 Block 渲染为一个可聚焦的卡片
- 内容区域是一个文本编辑器，操作生成 `UpdateBlock` op
- 类型下拉切换到 `BlockType` 枚举值，触发 `UpdateBlock(type: ...)`
- 点击 ✕ 执行 `DeleteBlock`
- 拖拽把手触发 `MoveBlock`（先不实现，后续加）

### 2. BlockType → 类型专属渲染器

每种类型一个 Widget，switch(block.type) 分发：

| BlockType | Widget | 逻辑 |
|-----------|--------|------|
| page | 页面容器（划线边框） | 渲染子块列表 |
| paragraph | 文本行（默认） | 无特殊样式 |
| heading | H1-H6 大字 | data.level → fontSize |
| todo | 行首 ☐ / ☑ 复选框 | data.checked → 勾选状态，点击生成 UpdateBlock |
| toggle | ▶ / ▼ 折叠头 | 点击展开/收起子块 |
| bulletListItem | • 前缀 | 嵌套缩进 |
| orderedListItem | 1. 2. 3. 前缀 | data.number |
| quote | 左侧灰色竖线 + 斜体 | 块引用样式 |
| code | 深色背景等宽字体 | data.language 标签 |
| divider | ─── 横线 | 不可编辑 |
| callout | 彩色背景 + 图标 | data.icon |
| image | 图片（占位/加载） | data.src |
| embedCard | 卡片样式 | data.title / subtitle |
| bookmark | 链接预览卡片 | data.url / favicon |
| equation | LaTeX 渲染（先用文字占位） | data.latex |
| database | 表格视图 | 子 Page 作为行 |
| columnList | 水平 flex 布局 | 子 column 按 ratio 分宽 |
| column | flex 子项 | data.ratio |
| syncedBlock | 灰色虚线框 + "同步自..." | data.refBlockId |

### 3. RichText + Span → 内联编辑器

- 使用一个自定义 TextEditingController
- 文本变更时实时构建 `List<Span>`：
  - 无格式文字 → `Span.text(text)`
  - 选中文字 + 点格式按钮 → 拆分 Span，应用 `InlineFormat`
- 每次失焦或定时保存生成 `UpdateBlock(content: newRichText)` op

### 4. InlineFormat → 格式工具栏

```
[B] [I] [Code] [S] [🔗] [@] [🎨]
```

- 选中部分文字后点击：
  - B → 包装为 `BoldFormat`
  - I → `ItalicFormat`
  - Code → `InlineCodeFormat`
  - S → `StrikethroughFormat`
  - 🔗 → 弹窗输入 url → `LinkFormat(url)`
  - @ → 弹窗选择已有块 → `MentionFormat(blockId)`
  - 🎨 → 颜色选择器 → `ColorFormat(color)`

- 格式与 Span 的分割规则：
  ```
  "Hello beautiful world"
  选中 "beautiful" 加粗 →
  [Span("Hello "), Span("beautiful", Bold), Span(" world")]
  ```

### 5. BlockData → 属性面板

右侧属性面板，根据选中 Block 的 type 显示不同的表单：

```
选中 heading:
  级别: [H1 ▼]    ← 1-6 下拉

选中 todo:
  完成: [☑]        ← 复选框

选中 code:
  语言: [dart  ▼]   ← 文本输入

选中 image:
  图片 URL: [input]  ← 文本输入
  说明:    [input]

选中 column:
  比例: [0.5]       ← 数字输入
```

- 修改属性生成 `UpdateBlock(data: newData)` op

### 6. BlockTree → 编辑器面板

- 输入 `List<Block>` 渲染递归的块列表
- 每次插入/删除/移动操作后重建 `FlatBlock` 列表
- 通过 `BlockTree.changes` Stream 监听增量变更

```
BlockTree → flat list by DFS → ListView.builder
    ↓                                    ↑
  insert/update/remove/move         setState / rebuild
```

### 7. BlockPath → 面包屑

```
📂 Root > Page 1 > H1: 设计文档
```

- 监听选中块变化，调用 `BlockTree.pathToRoot(selectedId)`
- 每段可点击跳转

### 8. BlockOp + OperationHistory → 撤销/重做

```
[↩ 撤销] [↪ 重做]   操作日志(3)
                      1. insert paragraph "新内容"
                      2. update heading → level 2
                      3. delete todo "买东西"
```

- 点击撤销 → `history.undo()` → 自动反向执行 → UI 更新
- 操作日志列表显示最近 N 条 opType + 摘要
- 每条日志可点击"反查"看完整 op 内容

### 9. OpValidator → 错误提示

```
⚠️ 验证错误：不能删除根节点
```

- `BlockEditorController.applyAiOps()` 返回错误时显示
- 红色横幅，自动消失或手动关闭

### 10. BlockId → 调试面板

```
Block ID: a1b2c3d4-e5f6-7890-abcd-ef1234567890  [复制]
Parent:   xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  [跳转]
Depth:    3
Path:     root > page > toggle > paragraph
```

- 每个块右键/长按 → 显示调试信息
- 与 `FlatBlock.depth` 数据联动

### 11. MarkdownBridge → 导入导出

```
[📥 导入 Markdown]   [📤 导出 Markdown]
```

- 导入：弹出 TextField 粘贴 markdown → `MarkdownBridge.parseMarkdown()` → 插入树
- 导出：`MarkdownBridge.exportToMarkdown(tree)` → 复制到剪贴板

### 12. Workspace → 页面 Tab 栏

```
[📄 笔记 1] [📄 笔记 2 (3)] [+]
```

- 每个 Page 是一个独立 `BlockTree`
- 切换 Tab → 切换当前编辑的树
- 新建 → 空 Page

---

## IV. Demo 初始化数据

启动时插入一组示例 Block，覆盖所有类型：

```
__root__
  └── page "Demo Page"
        ├── heading "块编辑器 Demo" (level: 1)
        ├── paragraph "这是一个 paragraph，支持**粗体**和*斜体*"
        ├── todo "实现 undo/redo" (checked: true)
        ├── todo "实现 Markdown 导入" (checked: false)
        ├── toggle "点击展开查看更多"
        │     ├── paragraph "嵌套内容"
        │     └── code "console.log('hello')" (language: js)
        ├── bulletListItem "无序 A"
        ├── bulletListItem "无序 B"
        ├── orderedListItem "第一步" (number: 1)
        ├── orderedListItem "第二步" (number: 2)
        ├── quote "这是一段引用"
        ├── divider
        ├── callout "提示：点击类型下拉切换块类型" (icon: 💡)
        └── columnList
              ├── column (ratio: 0.5)
              │     └── paragraph "左栏"
              └── column (ratio: 0.5)
                    └── paragraph "右栏"
```

---

## V. 实现优先级（分阶段）

### Phase 1 — 核心编辑（先跑通）
1. `Block → BlockCard` 的渲染
2. `BlockType` 类型专属渲染器（先做 6 个常用类型）
3. 选中/取消选中
4. 类型切换（下拉菜单 → UpdateBlock）
5. 删除块（✕ 按钮 → DeleteBlock）

### Phase 2 — 富文本格式
6. `RichText + Span` 内联编辑器（输入+展示）
7. `InlineFormat` 工具栏（先做 B/I/Code）
8. 格式与 Span 分割逻辑

### Phase 3 — 完整编辑功能
9. 新增块（回车/按钮 → InsertBlock）
10. 撤销/重做（OperationHistory）
11. `BlockData` 属性面板
12. 错误提示（OpValidator）

### Phase 4 — 附加功能
13. Markdown 导入/导出
14. 调试面板（BlockId / BlockPath）
15. 拖拽排序（MoveBlock）
16. 剩余 BlockType 渲染器

---

## VI. 文件结构（产出）

```
lib/lab/demos/
└── block_editor_demo/
    ├── block_editor_demo.dart    # DemoPage 入口
    ├── widget/
    │   ├── editor_panel.dart     # 编辑器主面板（BlockTree 渲染）
    │   ├── block_card.dart       # 单个块卡片
    │   ├── type_renderers.dart   # BlockType → 专属 Widget 分发
    │   ├── inline_editor.dart    # RichText 内联编辑组件
    │   ├── format_toolbar.dart   # InlineFormat 工具栏
    │   ├── property_panel.dart   # BlockData 属性面板
    │   ├── history_bar.dart      # 撤销/重做 + 操作日志
    │   ├── breadcrumb.dart       # BlockPath 面包屑
    │   ├── debug_panel.dart      # BlockId 调试信息
    │   ├── error_banner.dart     # OpValidator 错误提示
    │   └── page_tabs.dart        # Workspace 页面 Tab
    └── util/
        ├── demo_data.dart        # 初始化示例数据
        └── controller.dart       # BlockEditorController 封装
```
