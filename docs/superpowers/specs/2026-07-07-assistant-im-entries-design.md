# AI 助手首页 IM 条目化 — 设计

日期：2026-07-07
范围：`lib/screens/chat/home_page.dart`（单文件）

## 背景

首页 `HomePage` 当前用两个撑满屏幕的大卡片（`_ChatTypeCard`）作为功能入口：Agent（→ `AgentChatPage`）、Format（→ `FormatCompatibilityPage`）。需成熟化为 IM 会话列表风格的条目结构，方便后续扩展更多功能。

## 目标

- 用 IM 条目（`ListTile` 风格）替换大卡片：最左图标、中间主题+简介、最右进入箭头。
- 功能列表数据驱动，新增功能只需追加一条数据。
- 不改动目标页面（`AgentChatPage`、`FormatCompatibilityPage`）及导航行为。

## 设计

### 数据模型 `AssistantEntry`

一个条目 = 一份配置，纯数据 + 目标页面构造闭包，将「有哪些功能」与「怎么渲染」解耦：

```dart
class AssistantEntry {
  final IconData icon;
  final String title;      // 主题
  final String subtitle;   // 简介
  final Color Function(BuildContext) color;   // 主题色（依赖 Theme）
  final Widget Function(BuildContext) builder; // 目标页面
}
```

### 单一数据源 `_entries`

```dart
[ Agent 条目, Format 条目 ]   // 加第三个功能 = 追加一项
```

### `HomePage`

- 顶部保留标题区「AI 助手 / 选择功能」。
- 下方由 `Column` + `Expanded` 大卡片改为 `ListView.separated`，逐项渲染 `_AssistantTile`，`Divider` 分隔（缩进到头像右侧）。

### 条目组件 `_AssistantTile`（替换 `_ChatTypeCard`）

- 最左：圆形头像（`CircleAvatar`）内放 `icon`，用 entry 主题色。
- 中间：`title`（加粗）+ `subtitle`（次要色）。
- 最右：`Icons.chevron_right`。
- 整行 `InkWell` / `ListTile` 点击 → `Navigator.push(MaterialPageRoute(builder: entry.builder))`。

### 布局示意

```
┌──────────────────────────────────────┐
│  AI 助手                               │
│  选择功能                              │
├──────────────────────────────────────┤
│ (◉)  Agent                         ›  │
│      事件记录与分析                    │
│ ─────────────────────────────────────│
│ (◉)  Format                        ›  │
│      格式兼容性测试                    │
└──────────────────────────────────────┘
```

## 决策

- 头像形状：圆形（Telegram 风）。
- 保留顶部标题区「AI 助手／选择功能」。

## 不做（YAGNI）

- 不加末条消息预览、时间戳、未读红点、侧滑操作 —— 这些是真实会话才需要的，功能入口用不到。
- 不改目标页面与 provider。

## 测试

- 手动：`flutter analyze` 干净；运行后首页显示两条 IM 条目，点击各自进入对应页面，导航行为与旧版一致。
