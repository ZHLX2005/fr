---
name: uiux
description: Use when fixing UI/UX issues in this Flutter project (fr) — visual heaviness ("纯色太重", "左重右轻", "icon 纯色"), async data race conditions in nested sheets (database pickers, settings sheets), border-emphasis visual style, color decision (decorative vs functional), or any UX bug where users see "empty state" before data loads. Covers: (1) border-emphasis 边框强调式样式 — reduces visual weight via light tint + colored outline + colored foreground; (2) async load flag pattern — prevents race conditions where users tap into nested sheets before cache/IO completes; (3) 装饰性 vs 功能性 颜色决策矩阵.
---

# UIUX — 项目级 UI/UX 设计规范

小豆子 FR 项目的 UI/UX 设计 + 实战 bug 教训沉淀。

主文档承担**原则主线**（颜色决策 + 视觉权重），**特化专项**放 `references/`。

## 何时读哪个 ref

| ref | 何时读取 | 路径 |
|---|---|---|
| `[[border-emphasis-style]]` | 改造纯色填充按钮/icon 容器 / 减负密集按钮区 / "左重右轻" | `references/border-emphasis-style.md` |
| `[[async-load-flag-pattern]]` | 异步加载 + 用户快速点击嵌套 sheet 导致的 race condition（数据库列表"空空如也"、缓存竞态） | `references/async-load-flag-pattern.md` |

## 核心原则（主文档）

### 1. 视觉权重：避免纯色填充

填充式（`LinearGradient` / 饱和 `backgroundColor + white`）视觉重、密集按钮区"左重右轻"。
改造为**边框强调式**：浅 tint 底 + 同色描边 + 同色前景。详见 `[[border-emphasis-style]]`。

### 2. 颜色决策：装饰性 vs 功能性（规则相反）

| 元素类型 | 配色策略 |
|---|---|
| **装饰性**（导航卡片 icon、菜单项、纯展示） | **统一主题色** `Theme.of(context).colorScheme.primary` |
| **功能性**（操作按钮） | **撞色编码语义**：green=主操作、blue=查询、orange=暂停、red=危险、indigo=备用 |

详见 `[[border-emphasis-style]]` 的"颜色决策"章节。

### 3. 异步数据加载：必须用 loading flag 保护

**核心 bug 教训**（2026-07-04 Notion DB 选择器 race condition）：

嵌套 sheet 中（`ModalBottomSheet → ModalBottomSheet`），`initState` 里 `fire-and-forget` 调异步加载（SharedPreferences、网络），用户**在加载完成前**就点进下一层 sheet → 看到空数据 → 误以为"没有找到"。

**反模式**：
```dart
// ❌ 错误：fire-and-forget，无 race protection
void initState() {
  super.initState();
  _loadCache();  // 异步，但用户可能更快点 picker
}

Future<void> _pickDatabase() async {
  showModalBottomSheet(...);  // _databases 可能还是 []
}
```

**正确模式**：用 `_loadingXxx` 标志保护，picker 进入前等标志置位。详见 `[[async-load-flag-pattern]]`。

## 实战 bug 沉淀（references 主题）

| Bug | 沉淀 ref |
|---|---|
| 2026-07-04 Notion DB 选择器打开显示"空空如也" | `[[async-load-flag-pattern]]` |
| 2026 早期 Notion 图床按钮纯色填充、密集按钮区左重右轻 | `[[border-emphasis-style]]` |

## 反模式黑名单

- ❌ 给导航卡片配彩虹独立色（应统一主题色）
- ❌ 给操作按钮统一主题色（应撞色编码）
- ❌ `withOpacity(x)`（analyze 报 deprecated_member_use，应 `withValues(alpha: x)`）
- ❌ 删除/取消按钮去掉红色（破坏性操作永远保留 red）
- ❌ 嵌套 sheet 里 `fire-and-forget` 异步加载（race condition 必现）

## 检查清单

- [ ] 无残留 `LinearGradient` / 饱和 `color` 填充的 icon 容器
- [ ] 无残留 `ElevatedButton(backgroundColor: X, foregroundColor: white)` / `FilledButton`
- [ ] 装饰元素统一主题色，功能按钮撞色
- [ ] 破坏性操作保留红色
- [ ] 全用 `withValues(alpha:)`，无 `withOpacity`
- [ ] 嵌套 sheet 异步加载有 `_loadingXxx` flag 保护
- [ ] helper 复用样式，调用处一眼看清功能色
- [ ] loading / spinner 颜色与所在按钮同步

## 相关文件

- `lib/lab/demos/notion_image_host_demo.dart` — border-emphasis 实战范例（_outlinedBtnStyle helper、设置抽屉）+ race condition bug 起源
- `lib/lab/demos/api_test_demo.dart` — border-emphasis 实战范例