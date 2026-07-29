# Flutter-TimePage — 修改 Focus 面板（中间 tab 主页布局）

> ref：调整 `lib/core/focus/focus_home_page.dart` 内的布局骨架。**先读 `Flutter-TimePage-Focus时间模块设计` § 2-3 再看本 ref**。

## 触发场景

> 关键词：改中间 Time tab / 改 Focus 主页布局 / 改精选大卡 / 改网格密度 / 改入口顺序 / 调 visual。

改组件上下文（不含新增 / 删除 demo 操作流程），其他时序性改动去找对应 ref：

| 你要改的东西 | 走哪个 ref |
| --- | --- |
| 改 demo 注册标记 / 给 demo 加新 timePage / 改 kTimePageMeta | [[Flutter-TimePage-新增timePage工作流]] |
| 改 FocusStatsPage / 改心流空间 mode / 改 FocusSession | [[Flutter-TimePage-统计与心流空间扩展]] |
| 改 Lab 列表过滤 / 修 fr:// 路由可达 | [[Flutter-TimePage-Lab过滤与深链]] |

## 入口位置

`lib/core/focus/focus_home_page.dart` 是唯一需要修改的文件。固定布局锚点：

```
Scaffold
  └─ SafeArea
      └─ Consumer<FocusProvider>  (fp.isLoading 时显示 CircularProgressIndicator)
          └─ SingleChildScrollView  (padding: 24)
              └─ Column
                  ├─ _buildGreeting(context)
                  ├─ SizedBox(32)
                  ├─ _buildTodayCard(...)             ← sage 渐变 hero
                  ├─ SizedBox(24)
                  ├─ if (featured.isNotEmpty)
                  │     _FeaturedToolCard(...)
                  ├─ SizedBox(24)
                  └─ GridView.builder  crossAxisCount: 2, childAspectRatio: 1.6
```

## 常见修改动机与 SOP

### A. 调整 grid 项顺序 / 密度

**位置**：build() 中临时拼接 `grid` 列表（约 70-100 行）。

- **调顺序**：内部项（`数据统计`、`时间课表`）与 registry 项都在同一 `grid` 列表里 — 顺序 = 列表拼接顺序。直接移动 `_ToolItem.internal(...)` 在 `grid` 字面量里的位置。
- **3 列/4 列密度**：改 `GridView` 的 `crossAxisCount` 与 `childAspectRatio` 联动（推荐：3 列用 1.0、4 列用 0.9 起步）。
- **grid 整体换 ListView**：替换 `GridView.builder` 为 `ListView.builder`（注意外层已经在 `SingleChildScrollView` 内，必须 `shrinkWrap: true` + `physics: NeverScrollableScrollPhysics` 保持嵌套滚动行为）。

### B. 加一个新内部页入口（不是 demo）

**位置**：build() 中 `grid` 列表里。

```dart
_ToolItem.internal(
  label: '新页面',
  icon: Icons.<x>,
  color: const Color(0xFF<hex>),
  onTap: () => Navigator.push(context,
      MaterialPageRoute(builder: (_) => const NewPage())),
),
```

注意 `context` 在 Consumer<FocusProvider> builder 内可用——直接 `Navigator.push(context, ...)` 即可。

### C. 加第二个精选大卡

**位置**：

1. 在 `lib/core/focus/time_tools/const_time_pages.dart` 给第 2 个 demo 设 `featured: true`。
2. 改 build()：`featured.first` 不再够用，替换为 `featured.take(2)` + 滚动容器（如 `Row` 或 `Wrap`）+ 复用 `_FeaturedToolCard` 多次渲染。

**这是设计变动**，先与用户确认层数（2 卡 vs 1 卡是 UX 决策）。直接动 `featured.first` 是默认行为。

### D. 改 featured 选择策略（不依赖 `featured: true`）

**位置**：build() 中 `featured` 列表定义。

例如「按 `kTimePageMeta` 中注册顺序的第一项 featured」而非「`featured.first`」：

```dart
final featured = registryMetas.where((m) => m.meta.featured).take(1).toList();
```

或「永远把 clock 放精选」硬编码 — 找 build() 里 `registryMetas.where((m) => m.meta.featured)` 处替换。

### E. 改今日专注卡视觉

**位置**：`_buildTodayCard(context, fp, {...})` 单独 method（约文件中部）。

sage 渐变（`Color(0xFFB5C9A3) → Color(0xFFD4E4C4)`）+ White 文字 +「点击开始专注 →」提示是固定骨架。改：

- 渐变色 → 直接换两个 `colors` 字面量
- 「今日专注」文案 → 改字面量
- 加减字体大小 / icon → 调内部 `Text` / `Padding`
- 替换为不同构图（如加上图标） → 整体重写 method，但 onTap 行为保持

**Hero 卡不参与过滤逻辑**——单纯视觉，不动 `kTimePageMeta` 或 `timePage` 标记。

### F. 改 onTap 行为（默认跳 focus_timer）

- 改 hero tap 目标：build() 里 `_buildTodayCard(..., onTap: () => _navigateToTimer(context))` 替换为新动作。
- 改内部 grid 项 tap：`_ToolItem.internal(...)` 的 `onTap` 替换。
- 改 registry 项 tap：`FocusHomePage._openDemo(context, slug)` 是统一入口 —— 要扩展行为（如打开前埋点、打开前 confirm），改 `_openDemo` 单点。

## 边界守卫（不能跨出去的修改）

| 禁止 | 原因 |
| --- | --- |
| 不要在这里 import demo 实现类 | 路由机制已经兼容 demo 注册；import 会破坏对称 |
| 不要把 `timePage` 判断硬编码到 build() | 让 `filterByTimePage` 扩展做源头过滤；硬编码两套来源不一致 |
| 不要在 _ToolCard / _FeaturedToolCard 里加主题切换 | 卡片只读取 TimePageMeta 颜色，不感知 theme |
| 不要碰 `FocusProvider` 的统计字段（getTodayMinutes、getWeekMinutes 等）| 这些属于 `[[Flutter-TimePage-统计与心流空间扩展]]` 范畴 |

## 回归测试点

每次改布局后跑：

```bash
flutter analyze lib/core/focus/focus_home_page.dart
flutter build web --release   # 或 flutter analyze lib/ 兜底
```

进入中间 tab 手动验证 4 类 tap：
1. 今日专注卡 → 打开心流空间
2. 精选大卡 → 打开对应 demo
3. grid 内部页 → 打开对应内部页（数据统计 / 时间课表）
4. grid registry 项 → 打开对应 demo
