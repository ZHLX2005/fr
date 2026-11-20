---
name: A04-TimePage-Focus模块
description: FR 时间类模块（番茄钟/时钟/日历/节拍器/课程表）现状指南——Time 核心容器退役后的 Lab demo 形态、专注统计与心流空间扩展 SOP、深链与桌面 widget 接线。改任何时间类模块文件时读取。
---

# A04 — 时间类模块（番茄钟 / 时钟 / 日历 / 节拍器 / 课程表）

> **何时读**：改 `lib/core/focus/*`（番茄钟计时、统计、科目）或 `lib/core/timetable/*`（课表）、改时间类 demo 注册、加专注统计维度、改桌面 widget 深链时。
> 上游：Lab demo 注册与容器见 [[A03-Lab容器结构与扩展]]；别名兼容见 [[A06-Demo-Slug别名]]；通用验证门槛见 [[00-工程收尾与排障动线]]§1。

---

## 一、现状架构（2026-11 fr 33 起）

### 一句话

```
Time 核心容器（core-time / FocusHomePage）已退役
  → 时间类模块全部以普通 Lab demo 身份平铺在 Lab 列表：
      clock（时钟） / calendar（日历） / metronome（节拍器）
      focus（番茄钟，新增） / timetable（课程表，新增）
  → 底栏/钉选里每个 demo 都是一个可独立钉选的入口（demo:<slug>）
```

**不再存在的机制**（改动前的老设计，勿再依赖）：`DemoPage.timePage` 标记位、`filterByTimePage()` 扩展、`kTimePageMeta` 展示元数据表、`lib/core/focus/time_tools/const_time_pages.dart`、`lib/screens/containers/time_container.dart`（Focus 主页）。

### 时间类 demo 清单

| slug | demo 文件 | 页面 | 备注 |
|---|---|---|---|
| `clock` | `lib/lab/demos/clock_demo.dart` | 时钟页 | 桌面 widget 深链入口 |
| `calendar` | `lib/lab/demos/calendar_demo.dart` | 日历待办 | SQLite 任务 |
| `metronome` | `lib/lab/demos/metronome_demo.dart` | 节拍器 | 音频见 H 序列 |
| `focus` | `lib/lab/demos/focus_demo.dart` | `FocusTimerPage` | fr 33 新增：番茄钟 |
| `timetable` | `lib/lab/demos/timetable_demo.dart` | `TimetablePage` | fr 33 新增：课程表 |

前三个是**已有 demo 取消 timePage 标记后回归 Lab**；后两个是**从 Time 容器内部页提上来的新 demo**（原为 Focus 主页里的内部项）。

### 关键约束

| 约束 | 说明 |
|---|---|
| 时间类 demo 与普通 demo 平级 | 没有专属过滤/专属元数据表；展示信息全在各 demo 类的 `title` / `description` / `navIcon` |
| 番茄钟 / 课表走 `preferFullScreen = true` | demo 自管全屏布局，不套 demo 壳的 AppBar |
| 无专属 SVG | 图标集 53 张已用尽，`focus` / `timetable` 走 Material 兜底图标（`navIcon` override），并登记在 `test/lab/lab_icon_test.dart` 的 `noIconSlug` 白名单 |
| 深链双入口 | `fr://lab/demo/<slug>`（demo 壳）与 `fr://lab/core/focus` / `fr://lab/core/timetable`（直达业务页）都通 |

### 路由入口

| 路由 | 落点 | handler |
|---|---|---|
| `fr://lab/demo/focus` | 番茄钟（demo 壳） | `lab_demo_handler.dart`（按 slug 双索引查） |
| `fr://lab/demo/timetable` | 课程表（demo 壳） | 同上 |
| `fr://lab/core/focus` | `FocusTimerPage` 直达 | `lab_core_handler.dart` |
| `fr://lab/core/timetable` | `TimetablePage` 直达 | 同上 |
| `fr://lab/demo/clock` | 时钟（桌面 widget 入口） | `lab_demo_handler.dart` |

改 slug 必须同步 `lib/app_lifecycle/fr_method_channel_translator.dart` 的深链翻译表（硬编码 slug，见 [[A06-Demo-Slug别名]]）。

---

## 二、添加/修改时间类模块工作流

### 改已有时间类 demo

走标准 Lab demo 流程（[[A03-Lab容器结构与扩展]]§2）：改 demo 类的 `title` / `description` / `buildPage`，在 `lib/lab/lab_bootstrap.dart` 注册一次。

### 把业务页提为独立 demo（fr 33 的做法）

1. 在 `lib/lab/demos/<name>_demo.dart` 建 DemoPage 子类：`title`（中文）、`slug`（纯 ASCII）、`description`、`preferFullScreen`（全屏业务页填 true）、`navIcon`（无专属 SVG 时给 Material 兜底）、`buildPage` 返回业务页；
2. `lib/lab/lab_bootstrap.dart` 里 `import` + `registerXxxDemo()`；
3. 若该业务页原先是某个核心容器的内部项 → **删掉容器内的入口**（否则两处入口并存，用户两边都点一遍体验割裂），并同步删除容器文件、nav 目录条目、默认钉选里的旧 id；
4. 业务页本身**留在 `lib/core/<域>/`**（`lib/core/focus/`、`lib/core/timetable/`），demo 只是薄壳——demo 不搬业务代码；
5. 深链：若外部有硬编码链接指旧地址，在 `fr_method_channel_translator.dart` 与各 handler 里同步改指新 slug；
6. 收尾见本页「验证出口」。

### 新增一个时间类工具

新工具若是独立功能 → 直接建 Lab demo（走 A03）；若属于番茄钟/课表的功能扩展 → 走第三章（统计）或课表自身模块的文档。

---

## 三、扩展专注统计 / 心流空间

> 改番茄钟页面布局不在本章（那是普通页面改动），本章只管**统计维度**与**计时模型**。

### 当前模型契约

`FocusSession` 字段（**subjectId 已删除**）：
- `id`, `durationMinutes`, `startTime`, `endTime`
- `mode: FocusMode` — 番茄 / 自由枚举
- `note: String?` — 心流感言

持久化：只有一个 `SharedPreferences` key = `focus_sessions`（JSON 数组）。老数据 `subjectId` 字段被 `FocusSession.fromJson` 默默忽略。

计时器后台恢复：`FocusTimerProvider._sessionStartTime` + `_timerSecondsKey` + `_timerStartTimeKey` 三个 key；状态机 `idle / running / paused`。

### 4 步 SOP

**第 1 步：在 `FocusProvider` 加聚合方法**（不强加 UI，先让数据查询就绪 + 单测覆盖）。

```dart
// lib/core/focus/providers/focus_provider.dart
List<int> getDailyMinutesLast(int days) { ... }
int streakDays() { ... }
Map<FocusMode, int> aggregateMinutesByMode() { ... }
```

每个新方法 + 对应单测 `test/core/focus/focus_provider_test.dart`。

**第 2 步：UI 端加消费方法**：在统计页 `Column` 里插一个 `_buildXxx(focusProvider)`；整体走单一 `Consumer<FocusProvider>` builder——**不要再嵌套 Consumer**。

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

`focus_sessions` 之外的新 SP key 必须经过**专门评审**，避免后续出现 N+1 个 SP key。心流空间自身状态（`_sessionStartTime` 等内部 SP key）属例外，cold-start 恢复用。

### 反模式

| 反模式 | 后果 | 正确做法 |
| --- | --- | --- |
| 在 `FocusSession` 上新增「科目」字段 | **subject 概念已经删除**；复活破坏统计口径 | 用 `mode` 或新维度字段 |
| `FocusTimerProvider` 与 `FocusProvider` 各开一套聚合 | 数据双源 | 聚合只在 `FocusProvider` |
| 改 `_timerStartTime` 但不更新 `_restoreTimerState` | cold-start 后计时跳秒 | 改一处必改对称的另一处 |
| 在 Stats 页加 ListView 不限高度 | 无限列表 + 外层 SingleChildScrollView → 渲染卡死 | 限制 height / `shrinkWrap + NeverScrollableScrollPhysics` |
| 跨 await 用 builder `context` 不 re-guard | 「BuildContext 跨 async 空隙」lint | await 前捕获，await 后委托 State method |
| 新增时间工具时另建一套「时间页容器」 | 恢复已退役的 timePage 双入口模型 | 新工具直接做 Lab demo（第二章） |

### 测试矩阵

| 你修改的文件 | 必跑测试 |
| --- | --- |
| `focus_provider.dart` | `test/core/focus/focus_provider_test.dart` |
| `focus_timer_provider.dart` | `test/core/focus/focus_timer_provider_test.dart` |
| `focus_session.dart` | `test/core/focus/focus_session_test.dart`（含 legacy 兼容） |
| `focus_timer_page.dart` / `focus_stats_page.dart` | `flutter analyze` + 手动 |
| 时间类 demo 壳 | `test/lab/demo_slug_test.dart`、`test/lab/lab_icon_test.dart` |

---

## 四、回归不变量

| 不变量 | 违反症状 | 复现 |
| --- | --- | --- |
| **A.** 时间类 demo 在 Lab 列表可见 | Time 容器退役后入口消失 | 打开 Lab 列表找 clock / calendar / metronome / 番茄钟 / 课程表 |
| **B.** `fr://lab/demo/<slug>` 路由可达 | 桌面 widget 点无反应 | 桌面 widget → 时钟跳转 |
| **C.** `demoRegistry` 双索引（slug + title）完整 | slug 改名后 widget / 旧 fr link 全断 | `demo_slug_test.dart` 红灯 |
| **D.** Lab 去重按 `DemoPage` 实例而非 slug | 别名 slug 在 Lab 出现 N 张重复卡 | 扫 Lab 列表 |
| **E.** 番茄钟 / 课表**只有一个**入口形态 | 旧容器入口与新 demo 入口并存 | 底栏 + Lab 列表各点一遍 |

**E 是 fr 33 遗留的重点**：任何「删 Time 容器」类改动，都要确认旧入口（Focus 主页网格项、nav 目录 `core-time` 条目、默认钉选 `core-time`）一并清干净。

---

## 验证出口

- 改动范围跑 `flutter analyze`；时间类 demo 改动额外跑 `test/lab/demo_slug_test.dart` 与 `test/lab/lab_icon_test.dart`。
- 番茄钟/课表改动跑第三章测试矩阵对应项。
- 深链改动按「验证出口」手动过一条 `fr://lab/demo/<slug>`。
- 通用交付门槛见 [[00-工程收尾与排障动线]]§1。
