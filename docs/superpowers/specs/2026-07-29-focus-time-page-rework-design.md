# Focus 时间页改造 + 时间工具迁移 设计

- 日期：2026-07-29
- 范围：`lib/core/focus/`（中间 tab「Time」）+ `lib/lab/lab_container.dart` + 三个时间相关 demo + Lab 列表过滤
- 目标：① 删除「学习领域 / 学科」全部概念；② 今日专注卡可点击进入心流空间；③ 用 gamecenter 同款「标记字段 + slug 元数据表」把 clock / 日历 / 节拍器 作为入口接到 Focus 页（**不移动文件**），并从 Lab 列表隐藏。

## 背景

Focus 中间页当前结构：问候语 → 今日专注卡（不可点击）→ 学习领域科目网格 + 管理 → 快捷操作（数据统计 / 时间课表）。科目（`FocusSubject`）渗透在 home、timer、stats、provider 中。同时 `lab/demos/` 下已有成熟的时间 demo（clock / calendar / metronome），但目前只能从 Lab 进入。

### GameCenter 既有模式（本设计模仿对象）

- `DemoPage.type`（`DemoType.game`）标记游戏 demo；
- `lab_page.dart` 有 `excludeGames`（默认 `true`），过滤 `type != DemoType.game` —— **游戏默认不出现在 Lab 列表，只在游戏中心出现**；
- `game_center/const_game_center.dart` 用 `kGameMeta`（**slug 为键**、icon/gradient/mode/pattern）做展示元数据，**与 demo 实现文件解耦**（常量层不 import demo 类）；
- `game_center_page.dart` 用 `demoRegistry.getAll().filterByType(DemoType.game)` 取列表，`Navigator.push(DemoDetailPage(demo: demo))` 打开；
- demo 文件**不移动**，既是 demo 又出现在游戏中心。

时间页完全沿用这套思路，把 `type` 换成一个正交的布尔字段 `timePage`。

## 设计

### 1. `timePage` 标记字段

`lib/lab/lab_container.dart` 的 `DemoPage` 基类新增：

```dart
/// 时间页：true 时在 Focus 主页显示入口，并从 Lab 列表隐藏。
/// 与 [type] 正交（一个 demo 可同时是 game 或 util，timePage 只决定是否进 Focus）。
bool get timePage => false;
```

三个 demo 各加一行 override（文件原地不动）：

| 文件 | 类 | slug |
|---|---|---|
| `lab/demos/clock_demo.dart` | `ClockDemo` | `clock` |
| `lab/demos/calendar_demo.dart` | `CalendarDemo` | `calendar` |
| `lab/demos/metronome_demo.dart` | `MetronomeDemo` | `metronome` |

为对称起见，在 `lab_container.dart` 的 `DemoTypeFilter` extension 旁加一个便捷过滤（与 `filterByType` 并列，供 Focus 页使用）：

```dart
extension DemoTimePageFilter on Iterable<MapEntry<String, DemoPage>> {
  List<MapEntry<String, DemoPage>> filterByTimePage() =>
      where((e) => e.value.timePage).toList();
}
```

### 2. Lab 列表隐藏 timePage demo

`lib/screens/profile/lab/lab_page.dart` 当前：

```dart
widget.excludeGames
    ? demoRegistry.getAll().where((e) => e.value.type != DemoType.game)
    : demoRegistry.getAll()
```

改为（timePage 恒定排除，与 `excludeGames` 无关 —— 用户明确要求时间页「只在 Focus 显示」）：

```dart
final all = demoRegistry.getAll().where((e) => !e.value.timePage);
final visible = widget.excludeGames
    ? all.where((e) => e.value.type != DemoType.game)
    : all;
```

**注册表 / `fr://lab/demo/{slug}` 路由 / main.dart 桌面 widget 深链（`navigateToClock` → `fr://lab/demo/clock`）全部不动。** 只隐藏列表 UI。

### 3. 入口元数据注册表（模仿 `kGameMeta`）

新建 `lib/core/focus/time_tools/const_time_pages.dart`（放 focus 特性目录，对应 game_center 的 const 放 game_center 目录）：

```dart
class TimePageMeta {
  final String label;   // 覆盖 demo.title，统一中文（'Clock'→'时钟'）
  final IconData icon;
  final Color color;    // 取自现有 focus 莫兰迪调色板，保证视觉一致
  final bool featured;  // true → 占精选大卡
  const TimePageMeta({required this.label, required this.icon, required this.color, this.featured = false});
}

const Map<String, TimePageMeta> kTimePageMeta = {
  'clock':     TimePageMeta(label: '时钟',   icon: Icons.access_time_rounded,     color: Color(0xFFB5C9A3), featured: true),
  'calendar':  TimePageMeta(label: '日历',   icon: Icons.calendar_month_outlined, color: Color(0xFF6B9DFC)),
  'metronome': TimePageMeta(label: '节拍器', icon: Icons.music_note_outlined,     color: Color(0xFFB39EB5)),
};
```

未登记 slug 不出现（Focus 页只渲染 `kTimePageMeta` 里有的 timePage demo）。`featured` 决定哪个 demo 占精选大卡（当前 = clock）。

### 4. Focus 主页重排（Hero + 精选大卡 + 2 列网格）

`lib/core/focus/focus_home_page.dart` 新结构：

```
问候语（保留 _buildGreeting 不变）
[今日专注 hero 卡]（sage 渐变，保留现样式）→ 点击进 FocusTimerPage（心流空间）
[精选大卡：时钟]（宽卡，clock demo）→ DemoDetailPage
[2 列网格]：日历 · 节拍器（registry）+ 数据统计 · 时间课表（内部页）
```

要点：

- **今日专注卡**变可点击：保留 `_buildTodayCard` 的 sage 渐变样式，加 `→`/「点击开始」提示，`onTap` → `Navigator.push(FocusTimerPage())`。
- **精选大卡** `_FeaturedToolCard`：渲染 `kTimePageMeta` 中 `featured==true` 的项（clock），宽卡，icon + 中文 label + 一句描述。`onTap` → `Navigator.push(MaterialPageRoute(builder: (_) => DemoDetailPage(demo: demoRegistry.getBySlug(slug)!)))`，与 gamecenter `_open` 完全一致。
- **网格** `_ToolCard`（统一莫兰迪卡片，复用现有 action button 视觉语言）：顺序 = `[日历, 节拍器]`（registry 中 `featured!=true` 的）+ `[数据统计, 时间课表]`（内部）。
  - registry 项 onTap 同上 → `DemoDetailPage`。
  - 内部项 onTap 走现有 `_navigateToStats` / `_navigateToTimetable`。
- 内部项也用一个轻量结构描述（icon/label/color），与 registry 项一起拼成统一 list 再渲染，避免分支。
- **打开后的 clock / 日历 / 节拍器页面保持各自原生主题（ZenColors / PaperPalette）不动** —— 跟游戏中心一样，只有 Focus 上的"入口卡"统一莫兰迪风格。各 demo 已自带 `MaterialApp` + `preferFullScreen: true`，行为与从 Lab 打开一致。

### 5. 彻底移除「学习领域 / 学科」

代码中无独立「主题」概念，「学科和主题」即学习领域/科目体系，整体删除（已确认 `FocusSubject` 系列无 focus 目录外的引用）：

- **删文件**：`lib/core/focus/models/focus_subject.dart`（`FocusSubject` / `FocusIcons` / `FocusColors` / `FocusSubjectPresets`）。
- **`FocusProvider`**（`providers/focus_provider.dart`）：去掉 `_subjects` / `subjects` / `addSubject` / `updateSubject` / `deleteSubject` / `getSubjectMinutes`；`_loadData`/`_saveData` 去掉 subjects 分支（只留 sessions）；`addSession` 不再回写科目 completedMinutes；`clearAll` 去掉 subjects 重置。**删除 `restoreTimerState` 及其 `_timerSecondsKey`/`_timerSubjectKey` 常量** —— 该方法唯一职责是把 subject 塞回计时器；计时态（state/秒数/开始时间）由 `FocusTimerProvider` 构造时自恢复，与 FocusProvider 无关。**保留** `_sessions` / `sessions` / `getTodayMinutes` / `getWeekMinutes` / `getHeatmapData`。
- **`FocusSession`**（`models/focus_session.dart`）：去掉 `subjectId` 字段及其 copyWith/toJson/fromJson 分支。`fromJson` 天然容忍旧 JSON 多余键（向后兼容老数据），`toJson` 不再写 `subjectId`。**保留 `FocusMode`（番茄/自由）** —— 不属于学科概念，不在本次范围。
- **`FocusTimerProvider`**（`providers/focus_timer_provider.dart`）：去掉 `_selectedSubject` / `selectedSubject` / `selectSubject` / `restoreSubject` / `_timerSubjectKey`；`_saveTimerState`/`_clearTimerState` 去掉 subject key 读写；`completeSession()` 创建 `FocusSession` 时不再写 `subjectId`。
- **`focus_timer_page.dart`**：去掉 `initialSubject` 参数、`initState` 里的 `selectSubject` 与 `focusProvider.restoreTimerState(...)` 调用（方法已删除）、顶栏 `Icons.category_outlined` 科目选择按钮与 `_showSubjectSelector` 整个方法；`data.FocusProvider` 的 import 若无其它用途一并去掉。进入即纯计时。
- **`focus_stats_page.dart`**：删 `_buildSubjectDistribution`；`_buildDayDetailSection` / `_buildRecentSessions` 去掉 subject 查找与图标/名称，改成纯「专注 · 时段 · N 分钟」（最近记录仍可显示 `FocusMode.label`）。保留本周卡 + 日历热力图 + 当日详情 + 最近记录。
- **`focus_home_page.dart`**：删 `_buildSubjectSection` / `_buildSubjectCard` / `_SubjectManagementSheet` / `_SubjectEditDialog` / `_showSubjectManagement` / `_navigateToTimer(subject)`，以及不再需要的 `provider` import 残留。

## 数据兼容

- 旧 `focus_sessions` JSON 里的 `subjectId` 键：`FocusSession.fromJson` 不再读它，自然忽略，老记录可正常加载（只是不再显示科目名）。
- 旧 `focus_subjects` JSON：不再加载（provider 不再读该 key），遗留键留在 SharedPreferences 无害。
- 计时器持久化：去掉 `_timerSubjectKey` 读写；运行/暂停/秒数/开始时间恢复逻辑不变。

## 不在范围

- 不改 `FocusMode`（番茄/自由）。
- 不动 clock / calendar / metronome demo 内部实现与主题。
- 不动桌面 widget 同步（`LabClockProvider` 仍在 main.dart 冷启动注册）。
- 不改底部 tab 结构（`XiaDouZiBottomBar`）。

## 验证

1. `flutter analyze` 干净（项目惯例：analyze 干净后自动 add/commit/push）。
2. 中间 tab：今日专注卡点击 → 心流空间可起停/完成，完成会写一条 session。
3. 时钟 / 日历 / 节拍器入口 → 各自原生页面正常打开与返回。
4. 数据统计页：无学科分布；当日详情 / 最近记录显示纯时长。
5. Lab 列表：不再出现时钟 / 日历 / 节拍器三项。
6. 桌面 widget 深链 `fr://lab/demo/clock` 仍可达（注册表与路由未动）。
