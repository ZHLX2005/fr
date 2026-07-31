# Flutter-TimePage — Focus 时间模块完整指南

> 单一长 ref：整个 time 模块的**架构 + 4 个独立方面**（加新工作流 / 改面板 / 统计与心流空间扩展 / Lab 过滤与深链）按章节一次性加载。
>
> **何时读这个 ref**：改任何 time 模块相关文件 — 改 `lib/core/focus/*`、动 `kTimePageMeta`、`timePage` 标记、Lab 过滤、桌面 widget 深链、新增 / 修改 time 工具时。**不要为了优化加载粒度而拆成多个 ref** — 这 5 个方面都同主题，强行拆开会让 ref 之间互相依赖 / 引用 / 重复定义，反而更难维护。
>
> **前置依赖**：`flutter-work-flow/SKILL.md`（Flutter 项目总约定）。**兄弟 ref**：`Flutter-DemoPage-slug抽象化与别名机制`、`Flutter-Lab容器-模块结构与重构模式`、`Flutter-游戏中心-扩展游戏路线`、`Flutter-Provider双重实例冲突-时钟wipe后数据恢复`。

---

## 一、架构（为什么这套设计稳定）

### 一句话

```
timePage 标记位 (DemoPage 上加一根 bool 旗)
  + kTimePageMeta 展示元数据注册表 (slug → TimePageMeta，模仿 kGameMeta)
  + Lab 列表过滤 (排除 timePage demo)
  + Focus 主页消费 (Hero 今日专注 + 精选大卡 + 2 列网格)
= 一个 demo 进 Lab + 进 Focus 时间工具，两个入口互斥、共享 slug 路由
```

整套设计是 `kGameMeta` 模式的镜像：demo 文件**不移动**，是否进 Focus 由 `timePage` 标记决定，是否进 Lab 由 `!timePage` 过滤决定，等价于「游戏 demo 默认 `type == DemoType.game`，进 Lab 时被 `excludeGames` 过滤出 Lab 但出现在游戏中心」。

### 关键抽象清单

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

### 三条数据流

**A. 注册流（demo 文件原地添加）**
```
lib/lab/demos/<demo>.dart
  └─ @override bool get timePage => true;
```
必须同时在 `kTimePageMeta` 加一条（路径 B）；否则 `FocusHomePage` 用 `where(kTimePageMeta.containsKey)` 过滤，未登记的 timePage demo **会进 Lab 但不出现在主页**。

**B. 展示元数据流（消费者查表）**
```
lib/core/focus/time_tools/const_time_pages.dart
  ├─ kTimePageMeta: const Map<String, TimePageMeta>   ← 必须 const（编译期固化）
  ├─ TimePageMeta: 4 字段 label/icon/color/featured
  └─ timePageMetaOf(slug) = kTimePageMeta[slug] ?? kFallbackTimePageMeta
```

**C. UI 渲染流（Focus 主页）**
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

### 与 gamecenter 双向对照表

| gamecenter | timePage | 等价 / 镜像 |
| --- | --- | --- |
| `DemoType.game` (enum) | `bool get timePage` (字段) | 都是「标记某 demo 进 X」 |
| `extension DemoTypeFilter.filterByType` | `extension DemoTimePageFilter.filterByTimePage` | 同形态 |
| `class GameMeta` + `kGameMeta` | `class TimePageMeta` + `kTimePageMeta` | 同「常量层不 import demo 实现」 |
| `gameMetaOf(slug)` + `kFallbackGameMeta` | `timePageMetaOf(slug)` + `kFallbackTimePageMeta` | 同占位防御 |
| `screens/profile/lab/game_center/const_game_center.dart` | `core/focus/time_tools/const_time_pages.dart` | 各自放在消费者目录 |
| `GameCenterPage` 渲染 | `FocusHomePage._ToolCard` 渲染 | 网格 / 列表 / featured 大卡不同组合 |
| `excludeGames` 过滤 | `!timePage` 直接过滤 | 各自在 Lab 列表处置 |

新增 timePage 与新增 game center 分类时，**复用相同的 3 步模式**（demo 内标记 → const 表里登记 meta → 容器页消费），这种对称是架构稳定性的根源。

---

## 二、添加新 timePage 工作流（3 步 SOP）

> 与 `lib/core/focus/time_tools/const_time_pages.dart` 文件顶部注释同源。

### 第 1 步：在 demo 类上声明 timePage

打开 `lib/lab/demos/<new_demo>.dart`，找到 DemoPage 子类，紧跟 `slug` 声明下方加：

```dart
@override
bool get timePage => true;
```

紧贴 slug 是惯例——一起 code review 时一眼看到所有 metadata。

### 第 2 步：在 `kTimePageMeta` 登记展示元数据

打开 `lib/core/focus/time_tools/const_time_pages.dart`，在 map 里**按 slug**（与第 1 步完全一致）追加：

```dart
'<your-slug>': TimePageMeta(
  label: '中文短标',         // 覆盖 demo.title（如 'Clock' → '时钟'）
  icon: Icons.<x>,
  color: Color(0xFF<hex>),   // 取 focus 莫兰迪调色板
  featured: false,           // 只有「精选大卡」位才 true
),
```

4 字段含义：
- `label` — 中文短标，**不是 demo.title**（demo.title 是英文 slug-title 镜像）。
- `icon` — 卡片主图标。
- `color` — 强调色；当前调色板：`0xFFB5C9A3` sage / `0xFF6B9DFC` blue / `0xFFB39EB5` mauve / `0xFF8B9DC3` slate-blue 等。
- `featured` — **最多 1 个 demo 设 true**。当前 `clock` 占着，新 demo 默认 `false`。

⚠️ 不登记会怎样：`FocusHomePage` 用 `where(kTimePageMeta.containsKey)` 过滤，**未登记的 timePage demo 不会出现在主页**（但仍会在 Lab 列表里 —— 因为 Lab 过滤只查 `timePage` 不查 kTimePageMeta）。这是当前设计的预期行为：未登记 = 隐藏但仍进 Lab。

### 第 3 步：跑测试 + analyze + 提交

```bash
flutter analyze lib/core/focus/ lib/lab/
flutter test test/core/focus/const_time_pages_test.dart
flutter test test/lab/demo_slug_test.dart
```

测试断言：
- `const_time_pages_test.dart` 第 1 个测试：「`kTimePageMeta` 涵盖期望的 3 个 slug」—— **必须更新它的 `containsAll` 列表** 加你的 slug，否则测试挂红。
- `demo_slug_test.dart`：「slug 纯 ASCII」—— slug 不能含中文。
- 「新增 demo 后 `_demos.length >= 35`」这条得看基准值变化。

### 自动接线：无需手动接 Focus 主页

`FocusHomePage._openDemo(slug)` 通过 `demoRegistry.getBySlug(slug)` 自动拿 demo 实例并 push `DemoDetailPage(demo)`。**无需 import 你的新 demo 类**。

路由可达性自动满足：`fr://lab/demo/<slug>` 由 `LabDemoHandler` 处理（`lib/core/schema/handlers/lab_demo_handler.dart`），不查 timePage 标记。桌面 widget 深链的硬要求详见第五章。

### 正反例

✅ DO
```dart
class MyToolDemo extends DemoPage {
  @override String get title => '我的工具';
  @override String get slug => 'my-tool';           // 纯 ASCII
  @override String get description => '一句话';
  @override bool get timePage => true;               // ← 第 1 步
  @override Widget buildPage(BuildContext context) { ... }
}

// kTimePageMeta 里：
'my-tool': TimePageMeta(
  label: '我的工具',
  icon: Icons.build_outlined,
  color: Color(0xFFB39EB5),  // 调色板内的颜色
),
```

❌ DON'T

| 反模式 | 后果 | 正确做法 |
| --- | --- | --- |
| 在 `lib/core/focus/` 里新建 `xxx_page.dart` 然后在 `FocusHomePage` import | 破坏 gamecenter 对称模型；fr:// 路由失效；Lab 不显示 | 永远走 demo 注册 |
| `featured: true` 给多个 demo | `featured.first` 非确定，抓哪个看 map 插入顺序 | 1 个即可；多精选属设计变动，先和用户确认 |
| 用中文 slug（`我的工具`） | demo_slug_test 必报 ASCII 错误；fr:// URI 解析崩溃 | 永远纯 ASCII 短词 |
| 在 `FocusHomePage` 用 `if (slug == '...') special-handling` 走分支 | 重复逻辑：让 featured 标识承担所有 hot path 选择 | 改 kTimePageMeta 的 `featured` 字段或加新字段 |
| 跳过 `const_time_pages_test.dart` 第 1 个测试更新 | 新 slug 没被断言 → 后续维护者不知你没登记 | 永远同步更新测试期望 |

### 自检清单

```bash
grep -rn "timePage" lib/lab/demos/<new>.dart        # 应该有 override
grep -rn "<new-slug>" lib/core/focus/time_tools/    # 应该在 kTimePageMeta
grep -rn "<new-slug>" test/core/focus/const_time_pages_test.dart  # 测试期望
flutter analyze lib/core/focus/ lib/lab/ && echo OK
```

---

## 三、修改 Focus 主页入口面板

> 入口位置：`lib/core/focus/focus_home_page.dart` 是唯一需要修改的文件。
> 改 demo 注册 / 改 kTimePageMeta 等加新 demo 操作 → 走第二章。
> 改统计 / 心流空间 → 走第四章。

### 固定骨架

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

### 6 类修改动机

**A. 调整 grid 项顺序 / 密度**：build() 中临时拼接 `grid` 列表（约 70-100 行）。顺序 = 列表拼接顺序；3 列用 `childAspectRatio: 1.0`、4 列 0.9；ListView 替换需 `shrinkWrap: true` + `physics: NeverScrollableScrollPhysics`。

**B. 加一个新内部页入口**（不是 demo）：
```dart
_ToolItem.internal(
  label: '新页面',
  icon: Icons.<x>,
  color: const Color(0xFF<hex>),
  onTap: () => Navigator.push(context,
      MaterialPageRoute(builder: (_) => const NewPage())),
),
```

**C. 加第二个精选大卡**（设计变动）：在 kTimePageMeta 给第 2 个 demo 设 `featured: true`；改 build() `featured.take(2)` + 滚动容器 + 复用 `_FeaturedToolCard`。**先和用户确认层数**——2 卡 vs 1 卡是 UX 决策。

**D. 改 featured 选择策略**：直接编辑 build() 里 `registryMetas.where((m) => m.meta.featured)` 表达式，例如「按 kTimePageMeta 注册顺序的第一项 featured」。

**E. 改今日专注卡视觉**：单独 method `_buildTodayCard(context, fp, {...})`。sage 渐变 + White 文字 +「点击开始专注 →」是固定骨架。Hero 卡不参与过滤逻辑——单纯视觉，不动 `kTimePageMeta` 或 `timePage` 标记。

**F. 改 onTap 行为**：今日专注卡 tap 改 `_buildTodayCard(..., onTap: ...)`；内部 grid tap 改 `_ToolItem.internal(...)`；registry 项 tap 改 `_openDemo` 单点扩展行为（埋点 / confirm 等）。

### 边界守卫（不能跨出去的修改）

| 禁止 | 原因 |
| --- | --- |
| 不要在这里 import demo 实现类 | 路由机制已兼容 demo 注册；import 破坏对称 |
| 不要把 `timePage` 判断硬编码到 build() | 让 `filterByTimePage` 扩展做源头过滤 |
| 不要在 _ToolCard / _FeaturedToolCard 加主题切换 | 卡片只读 TimePageMeta 颜色，不感知 theme |
| 不要碰 `FocusProvider` 的统计字段 | 属于第四章范畴 |

### 回归测试点

每次改布局后跑：
```bash
flutter analyze lib/core/focus/focus_home_page.dart
```

进入中间 tab 手动验证 4 类 tap：今日专注卡 / 精选大卡 / 内部 grid（统计/课表）/ registry grid。

---

## 四、扩展统计 / 心流空间 time 维度

> 改主页布局不在本章 —— 走第三章。

### 当前模型契约（2026-07-29 `c0039ae8` 提交后）

`FocusSession` 字段（**subjectId 已删除**）：
- `id`, `durationMinutes`, `startTime`, `endTime`
- `mode: FocusMode` — 番茄 / 自由枚举（**保留**，对应两种专注意图）
- `note: String?` — 心流感言

持久化：只有一个 `SharedPreferences` key = `focus_sessions`（JSON 数组）。老数据 `subjectId` 字段被 `FocusSession.fromJson` 默默忽略。

计时器后台恢复：`FocusTimerProvider._sessionStartTime` + `_timerSecondsKey` + `_timerStartTimeKey` 三个 key；状态机 `idle / running / paused`。

### 4 步 SOP

**第 1 步：在 `FocusProvider` 加聚合方法**（不强加 UI，先让数据查询就绪 + 单测覆盖）。

```dart
// lib/core/focus/providers/focus_provider.dart
List<int> getDailyMinutesLast(int days) { ... }
int streakDays() { ... }   // 连续专注天数
Map<FocusMode, int> aggregateMinutesByMode() { ... }
```

每个新方法 + 对应单测 `test/core/focus/focus_provider_test.dart`。

**第 2 步：UI 端加 `_buildXxx(focusProvider)` method**：

```dart
Widget _buildModeDistribution(FocusProvider fp) { ... }
```

加进 `build()` 里 `Column` 列表即可。整体走单一 `Consumer<FocusProvider>` builder——**不要再嵌套 Consumer**。

**第 3 步：心流空间 mode**（如加新 mode）：

1. 加 enum 值（`pomobox`, `deepwork` 等）
2. 给 `FocusModeExtension.label` + `description` 补分支
3. `FocusTimerProvider.completeSession()` 里硬编码 `mode: FocusMode.freeTime` —— 要按 mode 区分完成行为：要么选择器在 timer 页加 UI，要么默认 freeTime 允许 override
4. UI 测试：`test/core/focus/focus_timer_provider_test.dart` 验证 completeSession 不抛

**第 4 步：心流空间后台计时**：

- 复用 `FocusTimerProvider._sessionStartTime`（不能新建 timer 状态机）
- 新字段如果要持久化 → 加到 `_saveTimerState`，同时在 `_restoreTimerState` 反序列化
- 单一数据源原则：心流空间的「上次停了多久」「今日累计」统计应由 `FocusProvider` 提供，不在 timer 里再开一套

### 不引入新存储

`focus_sessions` 之外的新 SP key 必须经过**专门评审**，避免后续 Time 模块出现 N+1 个 SP key。心流空间自身状态（`_sessionStartTime` 等内部 SP key）属例外，cold-start 恢复用。

### 反模式

| 反模式 | 后果 | 正确做法 |
| --- | --- | --- |
| 在 `FocusSession` 上新增「科目」字段 | **subject 概念已经删除**；复活破坏 gamecenter 对称 + stats | 用 `mode` 或新维度字段 |
| `FocusTimerProvider` 与 `FocusProvider` 各开一套聚合 | 数据双源 | 聚合只在 `FocusProvider` |
| 改 `_timerStartTime` 但不更新 `_restoreTimerState` | cold-start 后计时跳秒 | 改一处必改对称的另一处（见兄弟 ref `Flutter-Provider双重实例冲突-时钟wipe后数据恢复`）|
| 在 Stats 页加 ListView 不限高度 | 无限列表 + 外层 SingleChildScrollView → 渲染卡死 | 限制 height / `shrinkWrap + NeverScrollableScrollPhysics` |
| 跨 await 用 builder `context` 不 re-guard | 「BuildContext 跨 async 空隙」lint（cad94527 教训）| 捕获 / re-guard 详见底部错误案例 |

### 测试矩阵

| 你修改的文件 | 必跑测试 |
| --- | --- |
| `focus_provider.dart` | `test/core/focus/focus_provider_test.dart` |
| `focus_timer_provider.dart` | `test/core/focus/focus_timer_provider_test.dart` |
| `focus_session.dart` | `test/core/focus/focus_session_test.dart`（含 legacy 兼容）|
| `focus_stats_page.dart` | `flutter analyze` + 手动 |
| `focus_timer_page.dart` | `flutter analyze` + 手动 |

---

## 五、Lab 列表过滤 + 桌面 widget 深链

> 改主页布局 / 改 demo 注册都不在本章——前面章节。

### 4 个不变量（错过一个就翻车）

| 不变量 | 违反症状 | 复现 |
| --- | --- | --- |
| **A.** `timePage` demo 必须从 Lab 列表消失 | 用户两边都点一遍，体验割裂 | 打开 Lab 列表看是否见到 clock / calendar / metronome |
| **B.** `fr://lab/demo/<slug>` 路由必须可达（含 timePage demo）| 桌面 widget 点无反应 | Android Launcher 长按主屏添加 widget → 跳失败 |
| **C.** `demoRegistry` 双索引（slug + title）不被破坏 | slug 改名后 widget / 旧 fr link 全断 | `demo_slug_test.dart` 红灯 |
| **D.** Lab 去重按 `DemoPage` 实例而非 slug | 别名 slug 在 Lab 出现 N 张重复卡 | 扫 Lab 列表 |

**重要**：timePage demo 不动 Lab 过滤的运行时路径，只动 `_demos` 初始化的过滤逻辑。删除过滤会把 timePage demo 也放进 Lab。

### Lab 过滤机制（`lib/screens/profile/lab/lab_page.dart`）

```dart
final all = demoRegistry.getAll().where((e) => !e.value.timePage);   // ← 不变量 A
_demos = (widget.excludeGames
        ? all.where((e) => e.value.type != DemoType.game)
        : all)
    .where(seen.add)                                                  // ← 不变量 D
    .toList();
```

**顺序铁律**：`!timePage` 必须最先，否则 `excludeGames==false` 的路径可能漏。`seen.add` 在最后按 `DemoPage` 实例去重，别名 slug 只显示一次。

### `fr://lab/demo/<slug>` 路由（不变量 B）

路由 handler：`lib/core/schema/handlers/lab_demo_handler.dart`

```dart
class LabDemoHandler extends FrRouteHandler {
  static const _prefix = 'lab/demo/';
  @override
  Widget build(BuildContext context, FrRouteMatch match) {
    final demoKey = match.authority.substring(_prefix.length);
    final demo = demoRegistry.get(demoKey);  // 双索引查
    if (demo == null) return _NotFoundPage(message: '未找到 Demo: $demoKey');
    return _DemoDetailPage(demo: demo);
  }
}
```

**关键**：handler **不动 timePage 判断**——路由可达性自动满足 B。`demoRegistry.get(demoKey)` 走 slug 主索引 + title 副索引。

桌面 widget 入口 (`main.dart`)：
```dart
'navigateToClock'    => 'fr://lab/demo/clock',
'navigateToCalendar' => 'fr://lab/demo/calendar',
```

**硬编码 slug**——改 slug 必须同步改这两行（属于 `Flutter-DemoPage-slug抽象化与别名机制` ref 范畴）。

### 修改 Lab 过滤的边界

| 允许 | 禁止 |
| --- | --- |
| 加 `_hiddenFromLab: false` 反向豁免 | 改 `excludeGames` 语义 |
| 改去重顺序 | 把 `seen.add` 改成按 slug 去重 |
| 改排序方式 | 把过滤改成 lazy builder |
| 加排序字段如 `sortBy = .title` | 给 Lab panel 加新手势（见 `Flutter-Lab容器-模块结构与重构模式` ref）|

### 自检清单

完成后 grep 这几条：

```bash
grep -rn "where.*timePage" lib/screens/profile/lab/lab_page.dart   # Lab 过滤还在
grep -rn "filterByTimePage" lib/                                   # 还在用扩展（不要 inlined）
grep -rn "fr://lab/demo/clock" lib/main.dart                       # 桌面 widget 链可达
grep -rn "timePage" lib/core/schema/handlers/lab_demo_handler.dart  # 应该不命中（路由不感知）
flutter test test/lab/demo_slug_test.dart && echo OK
```

---

## 错误案例（沉淀，按发现日期倒序）

### [2026-07-29] 拆 4 个 ref 过度优化教训（key_board_3）

**错误操作**：第一次重构把 time 模块拆成 4 个独立 ref 文件（新增 / 改面板 / 统计扩展 / Lab 过滤）。

**实际后果**：用户反馈「ref 太少了，不要字数分割」——违反 key_board_3 主旨，「ref 是特化场景指导，不是为了拆而拆」。4 个 ref 内章节相互引用，反而定义凌乱（`DemoPage.timePage` / `kTimePageMeta` 等抽象在 4 个 ref 都出现）。

**正确做法**：保留单一长 ref，按主题内章节（同主题下 4 个不同方面）组织 —— key_board_3 的「主题才是判据」原则。同主题内的不同方面应该在一个文档里用章节组织，用锚点跳转，而不是分文件。

### [2026-07-29] `cad94527` BuildContext 跨 await 教训

`focus_timer_page.dart`「完成」按钮 onTap 在 `_showEndConfirmDialog` 闭包里使用 builder context 跨 await 调用 `_showCompletionDialog(context, ...)` —— Dart 分析器报「BuildContext 跨异步空隙，mounted 守卫不匹配（State.context vs builder context）」。

**修法**：在 await **之前**捕获 `focusProvider`，await 之后调 `_showCompletionDialog(session)` 委托给 State method，State method 内用 `this.context`（State.context 在 mounted 守卫下合法）。

### [2026-07-29] `c0039ae8` Lab 过滤初次集成

第一次集成 `timePage` 过滤时把过滤写成 `e.value.type != DemoType.time`（假设新加 enum 值）。**根因**：与 `DemoType.game` 误平行——以为 time 也要新 enum 值。task 4 改用 `bool get timePage` 字段（与 type 正交），改完测试才反应过来。

**正确做法**：过滤写 `!e.value.timePage`（bool 字段判断），**不要新增 `DemoType.time` enum 值**。如果业务演化让 time 必须有子类，再加 enum 值并保留 `timePage: true` 字段做兼容。

### [2026-07-29] c0039ae8 提交 SharedPreferences string/int 误用

`FocusTimerProviderTest` 测试 fixture 写 `'focus_timer_state': '0'`（字符串），但 `prefs.getInt()` 返回 null，导致 5 个测试全挂。SharedPreferences mock 对 `getInt` 严格要求 int 值。

**正确做法**：fixture 用 `'focus_timer_state': 1`（int），任何 `_timerStateKey` 都用 int 写。
