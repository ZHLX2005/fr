# Flutter-TimePage — Focus 时间模块设计与扩展路线

> 本 ref 沉淀提交 `c0039ae8fbff7a5a71ed20bbcfff9979a2cafa38` 后整个 time 模块的**架构 + 后续扩展剧本**。
> 阅读对象：在小豆子 FR Flutter 项目里碰「中间 Time tab / 心流空间 / 时间工具入口 / 统计页 time 维度」相关任务的任何人。
>
> **前置依赖**：`flutter-work-flow/SKILL.md`（Flutter 项目开发总约定）；与 `Flutter-DemoPage-slug抽象化与别名机制`、`Flutter-Lab容器-模块结构与重构模式`、`Flutter-游戏中心-扩展游戏路线` 是兄弟 ref，相互之间互引而非互替。

## 1. 一句话架构

```
timePage 标记位 (DemoPage 上加一根 bool 旗)
  + kTimePageMeta 展示元数据注册表 (slug → TimePageMeta，模仿 kGameMeta)
  + Lab 列表过滤 (排除 timePage demo)
  + Focus 主页消费 (Hero 今日专注 + 精选大卡 + 2 列网格)
  = 一个 demo 进 Lab + 进 Focus 时间工具，两个入口互斥、共享 slug 路由
```

整套设计是 `kGameMeta` 模式的镜像：demo 文件**不移动**，是否进 Focus 由 `timePage` 标记决定，是否进 Lab 由 `!timePage` 过滤决定，等价于「游戏 demo 默认 `type == DemoType.game`，进 Lab 时被 `excludeGames` 过滤出 Lab 但出现在游戏中心」。

## 2. 关键抽象清单（4 个核心 + 1 个组件变量）

| 抽象 | 位置 | 作用 |
| --- | --- | --- |
| `DemoPage.timePage` | `lib/lab/lab_container.dart` | 标记 demo 是否进 Focus（true）/ 是否退出 Lab 列表（true 则退）|
| `extension DemoTimePageFilter` | 同上 | `demoRegistry.getAll().filterByTimePage()`，与 `filterByType` 对称 |
| `class TimePageMeta` + `kTimePageMeta` | `lib/core/focus/time_tools/const_time_pages.dart` | slug → 展示元数据（label/icon/color/featured）的 const 表，**不 import 任何 demo 实现文件** |
| `timePageMetaOf(slug)` | 同上 + `kFallbackTimePageMeta` | 查表函数；前端只读消费 |
| `class _ToolItem` (内部分支 `_registry(slug)` / `_internal(...)`) | `lib/core/focus/focus_home_page.dart` | 把「demo 入口」和「内部页入口」统一为同一渲染列表，避免分支渲染 |

**布局三件套**（Focus 主页固定骨架）：
- `_FeaturedToolCard(slug: featured.first.slug, onTap: ...)` — 一张横跨整行的精选大卡（当前 = clock）
- `GridView.builder(crossAxisCount: 2, childAspectRatio: 1.6)` — 2 列网格：`[日历, 节拍器, 数据统计, 时间课表]`
- `_buildTodayCard(context, fp, onTap: () => _navigateToTimer(context))` — sage 渐变 hero，可点进心流空间

## 3. 三条核心数据流（任何扩展都依赖这三条路径）

### 路径 A：注册流（在 demo 文件原地添加）
```
lib/lab/demos/<demo>.dart
  ├─ 在 DemoPage 子类上添加 @override bool get timePage => true;
  └─ 路径 B 在 kTimePageMeta 追加一条
```

### 路径 B：展示元数据流（消费方依赖的常量表）
```
lib/core/focus/time_tools/const_time_pages.dart
  ├─ kTimePageMeta: const Map<String, TimePageMeta>  ← 必须 const（编译期固化）
  ├─ TimePageMeta: label/icon/color/featured (4 个字段)
  ├─ kFallbackTimePageMeta + timePageMetaOf(slug)
  └─ 没有 import 任何 demo 类（与 kGameMeta 完全对称的设计取舍）
```

### 路径 C：UI 渲染流（Focus 主页布局）
```
FocusHomePage.build()
  ├─ registrySlugs = demoRegistry.getAll()
  │     .filterByTimePage()                              ← 路径 A 标记的 demo
  │     .map(e.key).where(kTimePageMeta.containsKey)     ← 路径 B 须已登记
  ├─ featured = [s for s in registryMetas if s.meta.featured]
  ├─ grid = [_ToolItem.registry(slug) | s in non-featured]  // registry
  │      + [_ToolItem.internal('数据统计', ...),
  │         _ToolItem.internal('时间课表', ...)]         // 内部页
  ├─ 返回:
  │   Greeting → 今日专注卡(可点 → FocusTimerPage) → 精选大卡 → 2 列网格
  └─ _openDemo(slug) = Navigator.push(MaterialPageRoute(builder: (_) =>
                    DemoDetailPage(demo: demoRegistry.getBySlug(slug)!)))
```

## 4. 扩展剧本

> 每条剧本都假定你读完了第 2 节「关键抽象」和第 3 节「数据流」。

### 4.1 添加新 timePage 工作流（最频繁）

**目标**：在 `lib/lab/demos/` 下加一个新 demo，并让它出现在 Focus 主页入口。

**3 步 SOP**（与 `kTimePageMeta` 顶部注释一致）：

1. **`override bool get timePage => true;`** —— 在 demo 类里，紧跟 slug 声明便于 code review 一眼看到所有 metadata。
2. **在 `kTimePageMeta` 里追加一条** —— 按 slug 加，字段 4 个：`label / icon / color / featured`。`featured: true` 表示占精选大卡（只能一个，否则 first 取到的非确定）。
3. **`flutter analyze` 通过 → 在 `lib/screens/profile/lab/lab_page.dart` 检查过滤是否还工作** —— timePage demo 默认隐藏 Lab；如果需要重新在 Lab 露出，把 slug 重写为非 timePage demo 或单独加 expose 标记（**不推荐**：会破坏 gamecenter 对称模型）。

**打开机制**：无需手动接线，`FocusHomePage._openDemo(slug)` 自动通过 `demoRegistry.getBySlug(slug)` 拿到 demo 实例并 push `DemoDetailPage(demo)`。

**回归测试点**：每次新增都得跑这 3 件事，否则一定出事：
- `flutter analyze lib/core/focus/ lib/lab/`
- `demo_demo_slug_test.dart`（已有，验证 slug ASCII、注册双索引）
- `test/core/focus/const_time_pages_test.dart`（已存在，断言 `kTimePageMeta` 涵盖新增 slug）

**正反例**：

✅ DO
- 复制 `clock_demo.dart` 改 slug / title / buildPage；时间工作流走 DemoPage 标准模式
- 给新 demo 选择 `focus_module` 调色板内的颜色（避免灰色 / 纯黑破坏莫兰迪一致性）
- 引用已有的 widget 子模块（`lab/demos/(模块名)/`），保持单文件 / 扁平化（参见 `Flutter-work-flow` 末尾「多文件结构分离规则」）

❌ DON'T
- 不要在 `lib/core/focus/` 里新建一个 `xxx_page.dart` 再手工在 `FocusHomePage` 里 import —— 应当走 demo 注册，让 Lab 与 Focus 共享同一个入口开关
- 不要绕过 `DemoDetailPage` 直接 `Navigator.push(MaterialPageRoute(builder: (_) => 你自己的页面))` —— 会破坏 `fr://lab/demo/<slug>` 桌面 widget 深链可达性
- 不要把 `featured: true` 给多个 demo —— 当前实现 `featured.first` 取首个，行为非确定

### 4.2 修改 Focus 主页入口面板

**入口位置**：`lib/core/focus/focus_home_page.dart` —— `_ToolItem` 类 + `build()` 中的 `Column` 骨架。

**布局策略**（在用户选定的「Hero + 精选 + 网格」方案下）：

- **改顺序**：动 `grid` 列表的拼接顺序（registry 项先于内部页），只改 build() 里那个 `grid` 列表的赋值。
- **改密度**：`GridView` 的 `crossAxisCount` 与 `childAspectRatio` 都要相应变化；`crossAxisCount` 调大（3 / 4）配合 `childAspectRatio` 调小（1.0 → 1.3）。
- **改视觉**：`_ToolCard` 与 `_FeaturedToolCard` 在文件末尾，单独抽出来即改，不混 build()。
- **改顺序后想保留 featured 行为**：featured demo 永远是 `featured.first`（mapped list 在 build() 里临时排序约定），不要给多个 demo 开 `featured: true`（同 4.1 ✅/❌）。

**常见修改动机**：
- 加一个**内部页**（不是 demo）到主页（如未来某个 settings 入口）→ `_ToolItem.internal(...)` 一行。
- 调整**今日专注卡的 sage 渐变** → 单独动 `_buildTodayCard`，不动全局。
- 加一个**第二位精选大卡**（双精选）→ 改 `featured.first` 选中逻辑；这是设计变动，要先与用户确认层数。
- **移除/调换**数据统计或时间课表网格位置 → 调整 `_ToolItem.internal(...)` 在 `grid` 列表里的相对位置。

**回归测试点**：
- `flutter analyze lib/core/focus/focus_home_page.dart`
- 进入中间 tab 手动确认：今日专注可点 / 精选可点 / 4 个 grid 可点（数据统计、时间课表走内部路由）

### 4.3 扩展统计页 / 心流空间的 time 维度

> 这块是**进化路径**，涉及原有 `_buildDayDetailSection` / `_buildRecentSessions` / `FocusTimerProvider` 状态。当前 `subject` 概念已删除，`session` 模型只有 `durationMinutes / startTime / endTime / mode / note`。
>
> 想加新 time 维度（如「按 mode 分组的热力图」「连续专注天数」），不要回到已被删除的 subject 概念，而是直接在 `FocusSession` 上加字段或在 `FocusProvider` 上加聚合方法。

**SOP**：

1. **加聚合方法到 `FocusProvider`**（不强加 UI）：先在 `lib/core/focus/providers/focus_provider.dart` 加一个 `getXxx()` 统计方法，单测覆盖。
2. **UI 端 `_buildXxx(focusProvider)`**：在 `focus_stats_page.dart` 新建一个 method，整体走单一 `Consumer<FocusProvider>` builder。
3. **不引入新存储**：focus module 持久化只有 `focus_sessions` 一个 key（SharedPreferences），新维度只读这个，避免新 SP key 散乱。
4. **心流空间后台计时**：`FocusTimerProvider` 的 `_sessionStartTime` 是后台恢复用的；扩展 mode 区分（番茄 / 自由）时优先复用现有 `FocusMode` 枚举，不要新建。

**回归测试点**：
- `test/core/focus/focus_provider_test.dart` 加新聚合方法的断言
- 心流空间修改时必须 `flutter analyze lib/core/focus/focus_timer_page.dart` 并跑现有 `test/core/focus/focus_timer_provider_test.dart`

### 4.4 Lab 列表过滤 + 桌面 widget 深链避坑

**位置**：`lib/screens/profile/lab/lab_page.dart` 中 `_demos` 初始化（约 88 行）：
```dart
// 先按 timePage 标记排除时间页 demo（已在 Focus 主页展示），
// 再按 excludeGames 过滤游戏，最后按 demo 实例去重。
final all = demoRegistry.getAll().where((e) => !e.value.timePage);
_demos = (widget.excludeGames
        ? all.where((e) => e.value.type != DemoType.game)
        : all)
    ... // 去重 + 排序 ...
```

**关键不变量**（错过一个就翻车）：

| 不变量 | 违反后果 |
| --- | --- |
| `timePage` demo 必须在 Lab 列表消失 | 用户在两个入口都点一遍，体验割裂 |
| `fr://lab/demo/<slug>` 路由必须可达（含 timePage demo） | 桌面 widget 深链失败（`navigateToClock` 等），main.dart 里硬编码 |
| `demoRegistry` 双索引（slug + title）不被破坏 | slug 改名后 widget / 旧 fr link 全断 |
| Lab 去重按 `DemoPage` 实例而非 slug | 别名 slug（`rive-pendulum` / `demo-lab` 等）出现多张相同卡 |

**回归测试点**：
- `test/lab/demo_slug_test.dart` 已有 slug 索引 / 双索引 / ASCII 三件套断言 — 加新 demo 后必须跑这 5 个 test
- 手动验证：`adb shell am start ... fr://lab/demo/clock`（或 `flutter test` 的 fr_router 链路测试）

## 5. 与 gamecenter 模式的双向对照表

理解任一个都能推断另一个：

| gamecenter | timePage | 等价 / 镜像 |
| --- | --- | --- |
| `DemoType.game` (enum) | `bool get timePage` (字段) | 都是「标记某 demo 进 X」 |
| `extension DemoTypeFilter.filterByType` | `extension DemoTimePageFilter.filterByTimePage` | 同形态 |
| `class GameMeta` + `kGameMeta` | `class TimePageMeta` + `kTimePageMeta` | 同「常量层不 import demo 实现」 |
| `gameMetaOf(slug)` + `kFallbackGameMeta` | `timePageMetaOf(slug)` + `kFallbackTimePageMeta` | 同占位防御 |
| `screens/profile/lab/game_center/const_game_center.dart` | `core/focus/time_tools/const_time_pages.dart` | 各自放在消费者目录 |
| `GameCenterPage` 渲染 | `FocusHomePage._ToolCard` 渲染 | 网格 / 列表 / featured 大卡的不同组合 |
| `excludeGames` 过滤 | `!timePage` 直接过滤 | 各自在 Lab 列表处置 |

**含义**：新增 timePage 与新增 game center 分类时，**复用相同的 3 步模式**（demo 内标记 → const 表里登记 meta → 容器页消费）。这种对称是当前架构稳定性的根源。

## 6. 错误案例登记

### [2026-07-29] key_board_3 + c0039ae8 沉淀教训

| 错误操作 | 实际后果 | 正确做法 |
| -------- | -------- | -------- |
| 误判 `@flutterworkflow` 语义 | 误以为要新建 skill `.claude/skills/flutter-time-page-system/`，留下空目录 stub | 先读目标 skill 现有 `SKILL.md` 的触发场景；`@xxx-skill` 是给已存在 skill 加 ref，不是新建 |
| 试图用 key_board_2 直接建新 skill | 与 key_board_3 主旨冲突；混用模版会跨过 ref 加载引导链路 | `flutter-work-flow` 已有 9 个 ref，新增长度仅 ~150 行的应作为新 ref 入 `references/`，而不是新 skill |
| 设计时只考虑「主页布局」单一维度 | 漏掉 time 模块的 4 条实际扩展维度（添加 demo / 改面板 / 改统计 / Lab 过滤） | 在 SKILL.md § 1 用一句话架构定调，每个扩展场景各自一段，避免把多主题硬塞主文档 |
