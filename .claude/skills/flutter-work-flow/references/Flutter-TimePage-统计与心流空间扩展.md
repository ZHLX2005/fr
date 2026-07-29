# Flutter-TimePage — 统计与心流空间扩展

> ref：给 `FocusStatsPage` / 心流空间（FocusTimerPage）/ `FocusSession` 加新 time 维度数据。**先读 `Flutter-TimePage-Focus时间模块设计` § 2-3 再看本 ref**。

## 触发场景

> 关键词：加新专注统计 / 加心流 space mode / 改 FocusSession / 给时间热力图加新维度 / FocusProvider 加新聚合。

只涉及时间数据本身（session、统计、心流空间 mode）。**改主页布局 / 改 Lab 过滤 不属于本 ref**。

## 当前模型契约（2026-07-29 提交 `c0039ae8` 后）

`FocusSession` 字段（**subjectId 已删除**）：
- `id`, `durationMinutes`, `startTime`, `endTime`
- `mode: FocusMode` — 番茄 / 自由枚举（**保留**，对应两种专注意图）
- `note: String?` — 用户填的心流感言

持久化：只有一个 `SharedPreferences` key = `focus_sessions`（JSON 数组）；老数据的 `subjectId` 字段被 `FocusSession.fromJson` 默默忽略。

计时器后台恢复：`FocusTimerProvider._sessionStartTime` + `_timerSecondsKey` + `_timerStartTimeKey` 三个 key；状态机 `idle / running / paused`。

## 4 步 SOP（按时间维度加新功能）

### 第 1 步：在 `FocusProvider` 加聚合方法

> 不强加 UI，先让数据查询就绪 + 单测覆盖。

```dart
// lib/core/focus/providers/focus_provider.dart
List<int> getDailyMinutesLast(int days) { ... }
int streakDays() { ... }   // 连续专注天数
Map<FocusMode, int> aggregateMinutesByMode() { ... }
```

每个新方法 + 对应单测 `test/core/focus/focus_provider_test.dart`。

### 第 2 步：UI 端加 `_buildXxx(focusProvider)` method

```dart
// lib/core/focus/focus_stats_page.dart
Widget _buildModeDistribution(FocusProvider fp) { ... }
```

加进 `build()` 里 `Column` 列表即可。整体走单一 `Consumer<FocusProvider>` builder——**不要再嵌套 Consumer**。

### 第 3 步：心流空间 mode（如加新 mode）

`FocusMode` 枚举新增值时：

1. 加 enum 值（`pomobox`, `deepwork` 等）
2. 给 `FocusModeExtension.label` + `description` 补分支（`switch` 是 Dart 3 enum 全覆盖枚举，不会编译报警，但漏 case 会旧 mode 显示 undefined）
3. `FocusTimerProvider.completeSession()` 里硬编码 `mode: FocusMode.freeTime` —— 如要按 mode 区分完成行为：要么选择器在 timer 页加 UI，要么默认 freeTime 但允许 override
4. UI 测试：`test/core/focus/focus_timer_provider_test.dart` 验证 completeSession 不抛

### 第 4 步：心流空间后台计时

如果给心流空间加新计时行为（如间隔 / 长休 / 番茄钟自循环）：

- 复用 `FocusTimerProvider._sessionStartTime`（不能新建 timer 状态机）
- 新字段如果要持久化 → 加到 `_saveTimerState`，同时在 `_restoreTimerState` 反序列化
- **单一数据源原则**：心流空间的「上次停了多久」「今日累计」等统计应由 `FocusProvider` 提供，不在 timer 里再开一套

## 不引入新存储

当前 focus module 只有一个 `focus_sessions` SP key。新统计维度**只读这个 key**：

```dart
// ❌ 反例：开新 SP key 'focus_mode_stats' 散乱
// ✅ 正确：FocusProvider 提供聚合方法，按需调用 getXxx()
```

例外：`FocusTimerProvider._sessionStartTime` 等内部状态是新 SP key 是必要的（cold-start 恢复）。`focus_sessions` 之外的新 SP key 必须经过**专门评审**，避免后续 Time 模块出现 N+1 个 SP key。

## 测试矩阵

| 你修改的文件 | 必跑测试 |
| --- | --- |
| `focus_provider.dart` | `test/core/focus/focus_provider_test.dart` |
| `focus_timer_provider.dart` | `test/core/focus/focus_timer_provider_test.dart` |
| `focus_session.dart` | `test/core/focus/focus_session_test.dart`（含 legacy 兼容性） |
| `focus_stats_page.dart` | `flutter analyze` + 手动验证 Stats 页渲染 |
| `focus_timer_page.dart` | `flutter analyze` + 手动验证心流空间可起停/完成 |

## 反模式（focus/stats/timer 设计铁律）

| 反模式 | 后果 | 正确做法 |
| --- | --- | --- |
| 在 `FocusSession` 上新增「科目」字段 | **subject 概念已经被删除**（c0039ae8 提交整段移除）；复活会破坏 gamecenter 对称模型 + stats 页结构 | 用已有 `mode` 枚举或新维度字段，不要重建科目语义 |
| `FocusTimerProvider` 与 `FocusProvider` 各开一套聚合 | 数据双源，难同步，bug 难调 | 聚合只在 `FocusProvider` 一处；timer 报告完成事件给 provider 即可 |
| 改 `_timerStartTime` 但不更新 `_restoreTimerState` | cold-start 后计时跳秒（clock-vs-metronome 真实坑） | 改一处必然改对称的另一处，参见兄弟 ref `Flutter-Provider双重实例冲突-时钟wipe后数据恢复` |
| 在 Stats 页加 ListView 不限高度 | 无限列表 + 外层 SingleChildScrollView → 渲染卡死 | 限制 height / shrinkWrap + physics: NeverScrollableScrollPhysics |
| 跨 await 用 builder `context` 不 re-guard | 「BuildContext 跨 async 空隙」lint 在 cad94527 已修；保持 State-level method + `mounted` 守卫 | 见 ref 末尾提到的 `cad94527` 教训 |

## 错误案例（沉淀）

### [2026-07-29] `cad94527` BuildContext 跨 await 教训

「完成」按钮 onTap 在 `_showEndConfirmDialog` 闭包里使用 builder context 跨 await 调用 `_showCompletionDialog(context, ...)` —— Dart 分析器报「BuildContext 跨异步空隙，mounted 守卫不匹配（State.context vs builder context）」。

**修法**：在 await **之前**捕获 `focusProvider`，await 之后调 `_showCompletionDialog(session)` 委托给 State method，State method 内用 `this.context`（State.context 在 mounted 守卫下合法）。详见 `lib/core/focus/focus_timer_page.dart` 当前实现。
