# Flutter-TimePage-Focus 时间模块设计

> 主 SKILL.md 骨架：架构 + 关键抽象 + 数据流。任何改 time 模块的 Task 先扫一眼本文件，依动作加载对应 ref。

**前置依赖**：`flutter-work-flow/SKILL.md`（Flutter 项目总约定）。**兄弟 ref**：`Flutter-DemoPage-slug抽象化与别名机制`、`Flutter-Lab容器-模块结构与重构模式`、`Flutter-游戏中心-扩展游戏路线`、`Flutter-Provider双重实例冲突-时钟wipe后数据恢复`。

## 1. 一句话架构

```
timePage 标记位 (DemoPage 上加一根 bool 旗)
  + kTimePageMeta 展示元数据注册表 (slug → TimePageMeta，模仿 kGameMeta)
  + Lab 列表过滤 (排除 timePage demo)
  + Focus 主页消费 (Hero 今日专注 + 精选大卡 + 2 列网格)
= 一个 demo 进 Lab + 进 Focus 时间工具，两个入口互斥、共享 slug 路由
```

整套设计是 `kGameMeta` 模式的镜像：demo 文件**不移动**，是否进 Focus 由 `timePage` 标记决定，是否进 Lab 由 `!timePage` 过滤决定，等价于「游戏 demo 默认 `type == DemoType.game`，进 Lab 时被 `excludeGames` 过滤出 Lab 但出现在游戏中心」。

## 2. 关键抽象清单

| 抽象 | 位置 | 作用 |
| --- | --- | --- |
| `DemoPage.timePage` | `lib/lab/lab_container.dart` | 标记 demo 是否进 Focus（true）/ 是否退出 Lab 列表（true 则退）|
| `extension DemoTimePageFilter` | 同上 | `demoRegistry.getAll().filterByTimePage()`，与 `filterByType` 对称 |
| `class TimePageMeta` + `kTimePageMeta` | `lib/core/focus/time_tools/const_time_pages.dart` | slug → 展示元数据 (label/icon/color/featured) 的 const 表，**不 import 任何 demo 实现文件** |
| `timePageMetaOf(slug)` + `kFallbackTimePageMeta` | 同上 | 查表函数 + 占位 fallback |
| `class _ToolItem` (`.registry` / `.internal`) | `lib/core/focus/focus_home_page.dart` | 把「demo 入口」和「内部页入口」统一渲染列表，避免分支 |

**布局三件套**（Focus 主页固定骨架）：
- `_buildTodayCard(context, fp, onTap: () => _navigateToTimer(context))` — sage 渐变 hero，可点 → `FocusTimerPage()`
- `_FeaturedToolCard(slug: featured.first.slug)` — 1 张横跨整行的精选大卡
- `GridView.builder(crossAxisCount: 2, childAspectRatio: 1.6)` — 2 列网格：`[日历, 节拍器, 数据统计, 时间课表]`

## 3. 三条核心数据流

### A. 注册流（demo 文件原地添加）
```
lib/lab/demos/<demo>.dart
  └─ @override bool get timePage => true;
```
注意：必须同时在 `kTimePageMeta` 加一条（路径 B）；否则 timePage 标记无效（Focus 主页用 `where(kTimePageMeta.containsKey)` 过滤）。

### B. 展示元数据流（消费者查表）
```
lib/core/focus/time_tools/const_time_pages.dart
  ├─ kTimePageMeta: const Map<String, TimePageMeta>   ← 必须 const（编译期固化）
  ├─ TimePageMeta: 4 字段 label/icon/color/featured
  └─ timePageMetaOf(slug) = kTimePageMeta[slug] ?? kFallbackTimePageMeta
```

### C. UI 渲染流（Focus 主页）
```
FocusHomePage.build()
  ├─ registrySlugs = demoRegistry.getAll()
  │     .filterByTimePage()                              ← 路径 A
  │     .map(e.key).where(kTimePageMeta.containsKey)     ← 路径 B 必须已登记
  ├─ featured = [s for s in registryMetas if s.meta.featured]
  ├─ grid = [_ToolItem.registry(slug) | s in non-featured]
  │      + [_ToolItem.internal('数据统计', ...),
  │         _ToolItem.internal('时间课表', ...)]
  └─ 渲染: Greeting → 今日专注卡 → 精选大卡 → 2 列网格
            ↓ tap
            [今日专注卡]   _navigateToTimer(context)
            [精选 / grid]   _openDemo(context, slug) = Navigator.push(
                                       MaterialPageRoute(
                                           builder: (_) =>
                                           DemoDetailPage(demo: demoRegistry.getBySlug(slug)!)))
            [内部 grid 项]  item.onTap() （直接 Navigator.push）
```

## 4. 与 gamecenter 模式的双向对照表

| gamecenter | timePage | 等价 / 镜像 |
| --- | --- | --- |
| `DemoType.game` (enum) | `bool get timePage` (字段) | 都是「标记某 demo 进 X」 |
| `extension DemoTypeFilter.filterByType` | `extension DemoTimePageFilter.filterByTimePage` | 同形态 |
| `class GameMeta` + `kGameMeta` | `class TimePageMeta` + `kTimePageMeta` | 同「常量层不 import demo 实现」 |
| `gameMetaOf(slug)` + `kFallbackGameMeta` | `timePageMetaOf(slug)` + `kFallbackTimePageMeta` | 同占位防御 |
| `screens/profile/lab/game_center/const_game_center.dart` | `core/focus/time_tools/const_time_pages.dart` | 各自放在消费者目录 |
| `GameCenterPage` 渲染 | `FocusHomePage._ToolCard` 渲染 | 网格 / 列表 / featured 大卡不同组合 |
| `excludeGames` 过滤 | `!timePage` 直接过滤 | 各自在 Lab 列表处置 |

**含义**：新增 timePage 与新增 game center 分类时，**复用相同的 3 步模式**（demo 内标记 → const 表里登记 meta → 容器页消费）。这种对称是当前架构稳定性的根源。

## 5. 何时读哪个 ref

| ref | 何时读取 |
| --- | --- |
| [[Flutter-TimePage-新增timePage工作流]]   | 加新 demo / 加新 timePage 项 时（最频繁）|
| [[Flutter-TimePage-修改Focus面板]]       | 改中间 tab 入口布局 / 改 featured 选择 / 调网格密度 时 |
| [[Flutter-TimePage-统计与心流空间扩展]]  | 给 FocusStatsPage 加新 time 维度 / 改心流空间 mode / 改 FocusSession 字段 时 |
| [[Flutter-TimePage-Lab过滤与深链]]       | 修 Lab 列表漏 timePage demo / 桌面 widget 深链异常 / 多别名 demo 去重 时 |
