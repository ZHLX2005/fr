# fr 任务意图文档（taskget 领取 · 2026-08-11）

> 来源：kvcli todo `fr` topic（默认空间）。4 条 open，各成一簇。
> 领取时 id：#1 #2 #3 #4（回填 `todo done` 用这些 id）。
> 决策点已于 2026-08-11 经 AskUserQuestion 由用户拍板（见各簇「用户拍板」）。

## 聚类总览

| 簇 | 主题 | kvcli 任务 | 模块 |
|---|---|---|---|
| A | clock 记录：分钟精度 + record→clock 主题色 | #1 | `lib/lab/demos/clock/` + `lib/widgets/theme/zen_theme.dart` |
| B | 课表通用模式：只需一个「开始日期」 | #2 | `lib/core/timetable/service/config/` |
| C | clock 预设归零发声（just_audio 一次性音效） | #3 | `lib/lab/demos/clock/providers/` + `lib/services/` |
| D | 日历数字字体统一（定点改数字） | #4 | `lib/lab/demos/calendar/` + `lib/core/theme/typography.dart` |

四簇相互独立，可分别实现、分别回填、分别 commit。

---

## 簇 A — clock 记录：分钟精度 + record→clock 主题色（任务 #1）

### A1. 记录时间精确到「一天的分钟」

**现状/根因**：记录 `startTime` 全精度写入（`lab_clock_provider.dart:282-288`），但展示处只用 `MaterialLocalizations.formatShortDate`（仅日期、无时刻）：
- `clocks_tab.dart:282`（时钟记录列表）
- `dashboard_tab.dart:87`（仪表盘最近记录）
- `track_records_page.dart:64`（编排记录列表）

**目标**：三处显示改为带 `HH:mm` 的格式。**用户拍板：`YYYY-MM-DD HH:mm`**，直接复用现成 `formatRecordDate(DateTime)`（`zen_theme.dart:371-374`，输出 `YYYY-MM-DD HH:mm`）。

**范围**：仅改 3 处显示表达式；`startTime` 存储精度不动（无需截断到分钟）。确认 clock 模块文件能 import `zen_theme.dart`（`formatRecordDate` 所在），若已有 import 则直接复用。

**验收**：三处记录时间显示 `2026-08-11 09:35` 式；flutter analyze 干净。

### A2. record→新建 clock 默认颜色改主题色

**现状/根因**：record 左滑「新建」创建 clock（`clocks_tab.dart:416`）未传 color → provider 兜底 `'#2196F3'`（蓝色）：
- `lab_clock_provider.dart:231`（`createClock` 内 `color ?? '#2196F3'`）
- `lab_clock_provider.dart:131`（widget 同步兜底 `clock.color ?? '#2196F3'`）
- `clocks_tab.dart:145`、`track_editor_page.dart:150`（显示时解析兜底 `'0xFF2196F3'`）

**目标（用户拍板：色板首色 `#D4644B`）**：record→clock 默认色改为陶土色 `#D4644B`——即编辑器 `_palette.first`（`clock_editor_sheet.dart:23`），与「新建时钟」编辑器默认色一致，属主题色调。

**修法**：抽 `kDefaultClockColor = '#D4644B'` 常量（放 `lab_clock_provider.dart` 顶部供复用），替换 4 处蓝色兜底；显示兜底用 `'0xFFD4644B'` 写法保持解析一致。

**验收**：record→新建 clock 卡片为陶土色（非蓝）；flutter analyze 干净。

---

## 簇 B — 课表通用模式：只需一个「开始日期」（任务 #2）

**现状/根因**：设置页 `_buildDateField()`（`timetable_settings_page.dart:302-381`）两个入口 + 自动回退，全部服务于「周一对齐」，通用模式用不上：
1. 卡片 `InkWell` → `WeekCalculatorDialog`（两 Tab：周数推算 + 选日期回退周一，`timetable_week_calculator.dart:16-245`）；
2. 卡片下方独立按钮「选日期（自动对齐到最近周一）」直接 `showDatePicker`；
3. `_save()`（`timetable_settings_page.dart:50-60`）还自动把日期回退到周一（`findNearestMondayOnOrBefore`）。

课表本身无「时分」选择；「开始时间」滚轮属独立 doubletime demo，不在本任务范围。

**目标（通用模式 `isSchoolMode==false`）**：只保留**一个简单日期选择**——单个日期字段 → `showDatePicker`，无周数推算、无周一回退、无重复入口。**学校模式保留**现有周数推算 / 周一对齐逻辑。

**修法**：`_buildDateField()` / `_save()` 按 `isSchoolMode` 分支：通用模式走简化路径（直接存 `rawStart`）；学校模式走原逻辑。`WeekCalculatorDialog` / `findNearestMondayOnOrBefore` 仅学校模式引用。

**验收**：通用模式下设置页开始日期区只一个入口，选任意日期原样保存（不弹回周一、不弹周数推算）；学校模式行为不变；flutter analyze 干净。

---

## 簇 C — clock 预设归零发声（任务 #3）

**现状/根因**：`_startTimer`（`lab_clock_provider.dart:87-113`）每秒让 `remainingSeconds` 递减直到走负，**无「归零」检测、归零无声**（旧注释：震动/系统提示音已移除，倒计时结束由 metronome tick 提示）。原生引擎 `metronome.cpp` 无一次性播放 API，节拍器是连续引擎。

**「预设归零」含义（已与用户对齐）**：clock 倒计时剩余（remainingSeconds）从 `>0` 跨到 `<=0` 的瞬间。

**目标（用户拍板：方案 A — just_audio 一次性音效）**：
- 仿 `PieceSound`（`lib/core/game_audio/piece_sound.dart:16-52`，just_audio 单例 `setAsset + seek(0) + play`）新建 `ClockAlertSound` 单例，播放 `assets/audio/woodfish.wav`（clock 主题音，零新增资产；后续可换专属提示音 asset）。
- 在 `_startTimer` 里记录上一帧 `remainingSeconds`，检测 `>0 → <=0` 跳变时**触发一次**播放（幂等：只在跨零点瞬间触发，负值期间不再反复播）。
- 可顺带考虑：归零瞬间如节拍仍在响，是否 `BeatCoordinator.releaseOwnership` 停拍（归零即结束，合理；实现时按当前所有权实际行为定，列为可选项）。

**范围**：`lib/lab/demos/clock/providers/`（检测+触发）+ `lib/services/`（或 providers 旁）新增 `ClockAlertSound`。不动 C++ / FFI。

**验收**：clock 倒计时归零瞬间响一声木鱼；不重复连响；不抢占/中断正在运行的 beat（若未停拍）；flutter analyze 干净。

---

## 簇 D — 日历数字字体统一（任务 #4）

**现状/根因**：`AppText.title()/display()`（`lib/core/theme/typography.dart:11-23`）用 **`GoogleFonts.cormorantGaramond`**（衬线展示字体）；日历网格日期数字（`day_cell.dart:66-69` 用 `AppText.title().copyWith(fontSize:17)`）与含数字标题（`day_view.dart:23-24`、`month_view.dart:37-40`、`year_view.dart:44`、`annual_report_page.dart:25/45`）全用它。全 app 其它处（zen 系 / app 主题）为系统 sans-serif，仅日历（+ `stack_card_demo`）用衬线 → 不一致。

**目标（执行中用户改向：直接用正常默认字体，不在字体上加特殊样式）**：去掉这些数字/含数字文本的 Cormorant 衬线，改用**无 fontFamily 的默认 `TextStyle`**（保留颜色/字号/字重）→ 渲染走 app 默认字体，与全 app 一致。不动 `AppText` 定义（其它纯文字标题如人名仍可保留衬线，但本次范围只动数字/含数字文本）。

**范围**：
- `day_cell.dart:66-69` 网格日期数字。
- `day_view.dart:23-24`、`month_view.dart:37-40`、`year_view.dart:44`、`annual_report_page.dart:25/45` 含数字标题。
- 人名/弹窗纯文字标题（`person_detail_page`、`people_view`、`day_detail_sheet` 等）**不在范围**（非数字）。

**验收**：日历网格日期数字与含数字标题均为默认字体（与全 app 一致）；DayCell widget 测试断言 `fontFamily == null`；flutter analyze 干净。

---

## 执行顺序与回填

- 四簇独立，建议顺序：D（最小、纯字体）→ A（记录+颜色，中）→ B（课表，中）→ C（新音频行为，需真机听感）。
- 每簇完成后：① `flutter analyze` 干净 ② 按 [[feedback_autocommit_on_fix]] 立即 add/commit/push ③ `kvcli todo done <id> --result "..."` 逐条回填。
  - A→#1；B→#2；C→#3；D→#4。
- id 以 `kvcli todo list --topic fr` 的 open 为准（当前 #1#2#3#4）。
