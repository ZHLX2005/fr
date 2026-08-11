# fr 四簇修复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 fr 项目 kvcli todo `fr` topic 的 4 条待办——clock 记录分钟精度+record→clock 主题色(#1)、课表通用模式简化开始日期(#2)、clock 预设归零发声(#3)、日历数字特殊字体统一(#4)。

**Architecture:** 四簇相互独立，按 D→A→B→C 顺序实现，每簇独立 commit+push 并回填对应 `kvcli todo done`。D 用 AppText 新增 `titleSans/displaySans`（不动原 title/display）定点替换日历数字/含数字标题；A 复用现成 `formatRecordDate` 改 3 处记录显示 + 抽 `kDefaultClockColor`/`resolveColor` 替换 4 处蓝色兜底；B 抽 `resolveStartDateIso` 纯函数 + 通用模式只留单个日期选择；C 仿 `PieceSound` 建 `ClockAlertSound` just_audio 单例 + `crossedZero` 纯函数在每秒 tick 检测归零触发一次。

**Tech Stack:** Flutter (Dart), provider/riverpod, shared_preferences, just_audio（已依赖 ^0.9.40）, zen_theme 静态设计系统, GoogleFonts。

## Global Constraints

- 每簇完成后 `flutter analyze` 必须 **0 新增 error/warning**（基线：当前 master 干净）。
- 每簇 analyze 干净后立即 `git add/commit/push`（[[feedback_autocommit_on_fix]]，不要问用户）。
- **test/ 目录被 .gitignore 忽略**（[[test_gitignore_force_add]]）：新增测试文件一律 `git add -f test/...`，否则不跟踪。
- 每簇完成后 `kvcli todo done <id> --result "..."` 回填（id 以 `kvcli todo list --topic fr` 的 open 为准，当前 #1#2#3#4；簇 D→#4、A→#1、B→#2、C→#3）。
- 主题色调常量：`ZenColors.sage`(0xFF7A9A7E)、`mutedRed`(0xFFA0594A)、`ink`(0xFF2C2C2C)；clock 编辑器色板首色 `#D4644B`（陶土）；`formatRecordDate`（`zen_theme.dart:371`）输出 `YYYY-MM-DD HH:mm`。
- 遵循现有 `zen_theme`/`AppText`/`EmphasisButton` 模式，不改设计系统语义；不动 `AppText.title()/display()` 的衬线定义。
- 归零发声用 `just_audio`，asset = `assets/audio/woodfish.wav`（clock 主题音，零新增资产）。
- Flutter 命令在仓库根 `D:\code\a_dart\prj\fr` 执行。

---

# Part D — 日历数字特殊字体统一（#4）

**根因（已读码确认）：** `AppText.title()/display()`（`lib/core/theme/typography.dart:11-23`）用 `GoogleFonts.cormorantGaramond`（衬线）。日历网格日期数字（`day_cell.dart:66-69` `AppText.title().copyWith(fontSize:17)`）与含数字标题（`day_view.dart:23-24`、`month_view.dart:38-39`、`year_view.dart:44`、`annual_report_page.dart:25/45`）全用它 → 与全 app sans-serif 不一致。

**修法（执行中用户改向：直接用正常默认字体，不在字体上加特殊样式）：** 不新增 titleSans/displaySans；5 处含数字文本改用**无 fontFamily 的默认 `TextStyle`**（保留颜色/字号/字重），渲染走 app 默认字体。

## Task D1: 日历 5 处数字文本改默认字体 + widget 测试

**Files:**
- Modify: `lib/lab/demos/calendar/ui/widgets/day_cell.dart:66-69`（网格日期数字）
- Modify: `lib/lab/demos/calendar/ui/day_view.dart:23-24`（今日标题）
- Modify: `lib/lab/demos/calendar/ui/month_view.dart:38-39`（月标题）
- Modify: `lib/lab/demos/calendar/ui/year_view.dart:44`（`'$m 月'`）
- Modify: `lib/lab/demos/calendar/ui/annual_report_page.dart:25`（`'${cal.viewYear} 年度报表'`）、`:45`（`'$m 月'`）
- Test: `test/lab/demos/calendar/day_cell_default_font_test.dart`（新建）

- [ ] **Step 1: day_cell 网格数字改默认字体**

`day_cell.dart:66-69`：
```dart
                  Text(
                    '${date.day}',
                    // 直接用默认字体（不套 Cormorant 等特殊衬线），与全 app 一致。
                    style: TextStyle(
                      color: numberColor,
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
```

- [ ] **Step 2: day_view / month_view / year_view / annual_report 含数字标题改默认字体**

- `day_view.dart:23-24`：`AppText.display()` → `TextStyle(color: PaperPalette.ink, fontSize: 24, fontWeight: FontWeight.w600, height: 1.2)`。
- `month_view.dart:38-39`：`AppText.title()` → `TextStyle(color: PaperPalette.ink, fontSize: 18, fontWeight: FontWeight.w600, height: 1.25)`。
- `year_view.dart:44`：`AppText.title()` → 同上。
- `annual_report_page.dart:25`：`AppText.display()` → `TextStyle(fontSize: 24, w600, height: 1.2)`；`:45` `AppText.title()` → `TextStyle(fontSize: 18, w600, height: 1.25)`。

- [ ] **Step 3: 写 widget 测试（验证默认字体）**

```dart
// test/lab/demos/calendar/day_cell_default_font_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/ui/widgets/day_cell.dart';

void main() {
  testWidgets('日数字使用默认字体（无特殊衬线），与全 app 一致', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DayCell(
            date: DateTime(2026, 8, 11),
            // false 跳过农历小字/头像，只渲染日期数字，避免 AppText.caption
            // 的 GoogleFonts 在测试环境异步加载字体。
            inCurrentMonth: false,
            isToday: false,
            events: const [],
          ),
        ),
      ),
    );
    final text = tester.widget<Text>(find.text('11'));
    expect(text.style?.fontFamily, isNull);
    expect(text.style?.fontFamilyFallback, isNull);
  });
}
```

> 注：原计划曾考虑新增 `AppText.titleSans/displaySans`，但测试 google_fonts 异步加载在 flutter_test 极不稳定（loadFontIfNecessary rethrow + zone 竞态），且用户明确「不需要特殊样式」，故改用默认 `TextStyle`。

- [ ] **Step 4: analyze + test**

Run: `flutter analyze lib/lab/demos/calendar lib/core/theme/typography.dart && flutter test test/lab/demos/calendar/day_cell_default_font_test.dart`
Expected: analyze 0 新增 issue（既有 day_detail_sheet/people_view/person_form_sheet 告警为基线）；test PASS。

## Task D2: commit + todo done（#4）

- [ ] **Step 1: commit + push**

```bash
git add lib/lab/demos/calendar/ui/widgets/day_cell.dart lib/lab/demos/calendar/ui/day_view.dart lib/lab/demos/calendar/ui/month_view.dart lib/lab/demos/calendar/ui/year_view.dart lib/lab/demos/calendar/ui/annual_report_page.dart
git add -f test/lab/demos/calendar/day_cell_default_font_test.dart
git commit -m "fix(calendar): 日数字与含数字标题改用默认字体，与全 app 统一

#4: 去掉日历数字/今日/月/年/年度报表的 Cormorant 衬线，改无 fontFamily
的默认 TextStyle（保留颜色/字号/字重）。不新增特殊字体样式。
DayCell 默认字体 widget 测试过，analyze 干净。kvcli fr #4."
git push
```

- [ ] **Step 2: 回填 todo**

```bash
kvcli todo done 4 --result "日历数字字体统一完成: 日数字+今日/月/年/年度报表含数字标题去掉 Cormorant 衬线, 改无 fontFamily 默认 TextStyle(保留颜色/字号/字重), 与全 app 一致。DayCell 默认字体 widget 测试过, analyze 干净。commit <hash>"
```

---

# Part A — clock 记录分钟精度 + record→clock 主题色（#1）

**根因（已读码确认）：** 记录时间只用 `MaterialLocalizations.formatShortDate`（`clocks_tab.dart:282`、`dashboard_tab.dart:87`、`track_records_page.dart:64`）→ 只有日期无时分；record→新建 clock（`clocks_tab.dart:416`）不传 color → `createClock` 兜底 `'#2196F3'`（`lab_clock_provider.dart:231`），`_syncToWidget` 兜底同色（`:131`），显示解析兜底 `'0xFF2196F3'`（`clocks_tab.dart:145`、`track_editor_page.dart:150`）。

**修法（用户拍板：显示 `YYYY-MM-DD HH:mm`；默认色 `#D4644B` 色板首色）：** A1 三处显示换 `formatRecordDate`；A2 抽默认色常量与纯函数替换 4 处蓝色兜底。

## Task A1: 记录时间显示精确到分钟

**Files:**
- Modify: `lib/lab/demos/clock/widgets/clocks_tab.dart:282`
- Modify: `lib/lab/demos/clock/widgets/dashboard_tab.dart:87`
- Modify: `lib/lab/demos/clock/widgets/track_records_page.dart:64`

**Interfaces:**
- Consumes: `formatRecordDate(DateTime)`（`zen_theme.dart:371`，输出 `YYYY-MM-DD HH:mm`；3 文件均已 import `zen_theme.dart`）

> A1 是纯显示表达式替换（复用已存在的 `formatRecordDate`，零新逻辑），无可写失败测试的独立函数；验证 = analyze + 真机目视。

- [ ] **Step 1: clocks_tab 记录日期改分钟**

`clocks_tab.dart:282`，把

```dart
    final dateStr = MaterialLocalizations.of(context).formatShortDate(record.startTime);
```

改为

```dart
    final dateStr = formatRecordDate(record.startTime);
```

- [ ] **Step 2: dashboard 最近记录改分钟**

`dashboard_tab.dart:87`，把

```dart
                                  '${MaterialLocalizations.of(context).formatShortDate(r.startTime)} · 实际 ${formatDuration(r.durationSeconds)}',
```

改为

```dart
                                  '${formatRecordDate(r.startTime)} · 实际 ${formatDuration(r.durationSeconds)}',
```

- [ ] **Step 3: track 记录改分钟**

`track_records_page.dart:64`，把

```dart
    final dateStr = MaterialLocalizations.of(context).formatShortDate(record.startTime);
```

改为

```dart
    final dateStr = formatRecordDate(record.startTime);
```

- [ ] **Step 4: analyze + 真机目视**

Run: `flutter analyze lib/lab/demos/clock`
Expected: 0 issues（无未用 import 告警——3 文件仍用 Material 组件，无需删 import）。真机：时钟记录/仪表盘/编排记录显示 `2026-08-11 09:35` 式。

## Task A2: record→clock 默认色改主题陶土色 + 单测

**Files:**
- Modify: `lib/lab/demos/clock/providers/lab_clock_provider.dart:131`、`:231`（兜底色）
- Modify: `lib/lab/demos/clock/widgets/clocks_tab.dart:145`（显示解析兜底）
- Modify: `lib/lab/demos/clock/widgets/track_editor_page.dart:150`（显示解析兜底）
- Test: `test/lab/clock_default_color_test.dart`（新建）

**Interfaces:**
- Produces: `LabClockProvider.kDefaultClockColor`（`static const String = '#D4644B'`）、`LabClockProvider.resolveColor(String? color) -> String`

- [ ] **Step 1: 写失败测试**

```dart
// test/lab/clock_default_color_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/providers/lab_clock_provider.dart';

void main() {
  group('LabClockProvider.resolveColor', () {
    test('无颜色 → 主题默认陶土色 #D4644B（非蓝）', () {
      expect(LabClockProvider.resolveColor(null), '#D4644B');
    });
    test('有颜色 → 原样返回，不覆盖用户选择', () {
      expect(LabClockProvider.resolveColor('#7A9A7E'), '#7A9A7E');
    });
    test('默认色常量即编辑器色板首色', () {
      expect(LabClockProvider.kDefaultClockColor, '#D4644B');
    });
  });
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `flutter test test/lab/clock_default_color_test.dart`
Expected: FAIL — `resolveColor`/`kDefaultClockColor` 未定义。

- [ ] **Step 3: 实现常量 + 纯函数**

在 `lab_clock_provider.dart` 类体顶部（`static const String _storageKey` 附近）加：

```dart
  /// record→新建 clock 的默认色 —— 编辑器色板首色陶土（非原蓝色 #2196F3），fr #1。
  static const String kDefaultClockColor = '#D4644B';

  /// 颜色为空 → 主题默认陶土色；否则原样（不覆盖用户选择）。
  static String resolveColor(String? color) => color ?? kDefaultClockColor;
```

- [ ] **Step 4: 应用兜底色替换（4 处）**

`lab_clock_provider.dart:231`（createClock 内）：
```dart
      color: color ?? '#2196F3',
```
→
```dart
      color: resolveColor(color),
```

`lab_clock_provider.dart:131`（_syncToWidget 内）：
```dart
      color: clock.color ?? '#2196F3',
```
→
```dart
      color: resolveColor(clock.color),
```

`clocks_tab.dart:145`：
```dart
    final baseColor = Color(int.parse(clock.color?.replaceFirst('#', '0xFF') ?? '0xFF2196F3'));
```
→
```dart
    final baseColor = Color(int.parse(clock.color?.replaceFirst('#', '0xFF') ?? '0xFFD4644B'));
```

`track_editor_page.dart:150`：
```dart
                    final color = Color(int.parse(c.color?.replaceFirst('#', '0xFF') ?? '0xFF2196F3'));
```
→
```dart
                    final color = Color(int.parse(c.color?.replaceFirst('#', '0xFF') ?? '0xFFD4644B'));
```

- [ ] **Step 5: 运行测试，确认通过**

Run: `flutter test test/lab/clock_default_color_test.dart`
Expected: PASS（3 用例）。

- [ ] **Step 6: analyze + 真机目视**

Run: `flutter analyze lib/lab/demos/clock`
Expected: 0 issues。真机：clock 记录左滑「新建」→ 新 clock 卡片为陶土色 `#D4644B`（非蓝）；新建时钟编辑器默认色仍陶土。

## Task A3: commit + todo done（#1）

- [ ] **Step 1: commit + push**

```bash
git add lib/lab/demos/clock/providers/lab_clock_provider.dart lib/lab/demos/clock/widgets/clocks_tab.dart lib/lab/demos/clock/widgets/dashboard_tab.dart lib/lab/demos/clock/widgets/track_records_page.dart lib/lab/demos/clock/widgets/track_editor_page.dart
git add -f test/lab/clock_default_color_test.dart
git commit -m "feat(clock): 记录时间精确到分钟 + record→clock 默认陶土色

#1: 记录/仪表盘/编排记录显示 formatRecordDate(YYYY-MM-DD HH:mm);
    新增 kDefaultClockColor/resolveColor(编辑器色板首色 #D4644B),
    替换 4 处蓝色 #2196F3 兜底。
3 单测过(resolveColor), analyze 干净。kvcli fr #1."
git push
```

- [ ] **Step 2: 回填 todo**

```bash
kvcli todo done 1 --result "clock 记录分钟精度+主题色完成: 3 处记录显示改 formatRecordDate(YYYY-MM-DD HH:mm); record→clock 默认色 #D4644B(色板首色) 替换 4 处蓝兜底, resolveColor 3 单测过。analyze 干净。commit <hash>"
```

---

# Part B — 课表通用模式：只需一个「开始日期」（#2）

**根因（已读码确认）：** `_buildDateField()`（`timetable_settings_page.dart:302-381`）两个入口（卡片 InkWell→`WeekCalculatorDialog` 周数推算 + 独立「选日期（自动对齐到最近周一）」按钮），`_save()`（`:46-84`）还会把日期自动回退周一（`findNearestMondayOnOrBefore`）。全是「周一对齐」服务，通用模式（`_isSchoolMode==false`）用不上 → 混乱重复。

**修法（用户拍板：通用模式只留一个日期选择，学校模式不动）：** 抽 `resolveStartDateIso` 纯函数；`_buildDateField` 按模式分支，通用模式单字段直弹 `showDatePicker`。

## Task B1: resolveStartDateIso 纯函数 + 单测

**Files:**
- Modify: `lib/core/timetable/service/config/timetable_week_calculator.dart`（`findNearestMondayOnOrBefore` 之后加）
- Test: `test/core/timetable/start_date_resolver_test.dart`（新建）

**Interfaces:**
- Produces: `resolveStartDateIso(String rawStart, {required bool isSchoolMode}) -> String`（通用模式原样；学校模式回退最近周一；解析失败原样返回）

- [ ] **Step 1: 写失败测试**

```dart
// test/core/timetable/start_date_resolver_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/timetable/service/config/timetable_week_calculator.dart';

void main() {
  group('resolveStartDateIso', () {
    test('通用模式：任意日期原样保存（不回退周一）', () {
      // 2026-08-14 是周五
      expect(resolveStartDateIso('2026-08-14', isSchoolMode: false), '2026-08-14');
    });
    test('通用模式：周一也原样', () {
      expect(resolveStartDateIso('2026-08-10', isSchoolMode: false), '2026-08-10');
    });
    test('学校模式：周五回退到最近周一', () {
      expect(resolveStartDateIso('2026-08-14', isSchoolMode: true), '2026-08-10');
    });
    test('无法解析 → 原样返回', () {
      expect(resolveStartDateIso('not-a-date', isSchoolMode: false), 'not-a-date');
    });
  });
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `flutter test test/core/timetable/start_date_resolver_test.dart`
Expected: FAIL — `resolveStartDateIso` 未定义。

- [ ] **Step 3: 实现 resolveStartDateIso**

在 `timetable_week_calculator.dart` 的 `findNearestMondayOnOrBefore`（第 13 行）后加：

```dart
/// 解析起始日期：
/// - 通用模式（isSchoolMode=false）：任意日期原样保存，不回退周一（fr #2）；
/// - 学校模式：回退到该日期之前的最近周一；
/// - 解析失败：原样返回。
String resolveStartDateIso(String rawStart, {required bool isSchoolMode}) {
  DateTime? parsed;
  try {
    parsed = DateTime.parse(rawStart);
  } catch (_) {}
  if (parsed == null) return rawStart;
  final resolved = isSchoolMode ? findNearestMondayOnOrBefore(parsed) : parsed;
  return resolved.toIso8601String().split('T')[0];
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `flutter test test/core/timetable/start_date_resolver_test.dart`
Expected: PASS（4 用例）。

## Task B2: 通用模式日期字段简化 + _save 分支

**Files:**
- Modify: `lib/core/timetable/service/config/timetable_settings_page.dart:46-84`（`_save`）、`:299-381`（`_buildDateField`）

**Interfaces:**
- Consumes: `resolveStartDateIso`（B1 产出）

- [ ] **Step 1: _save 用纯函数替换手动回退**

`_save()` 中第 50-61 行，把

```dart
    // 用户输入任意日期 → 自动回退到该日期之前的最近周一
    final rawStart = _startDateController.text.trim();
    DateTime? parsed;
    try {
      parsed = DateTime.parse(rawStart);
    } catch (_) {}
    final mondayStart = parsed != null
        ? findNearestMondayOnOrBefore(parsed).toIso8601String().split('T')[0]
        : rawStart;
    if (mondayStart != rawStart) {
      _startDateController.text = mondayStart;
    }
```

改为

```dart
    // 通用模式原样保存；学校模式回退到最近周一（fr #2）
    final rawStart = _startDateController.text.trim();
    final startDateIso = resolveStartDateIso(
      rawStart,
      isSchoolMode: _isSchoolMode,
    );
    if (startDateIso != rawStart) {
      _startDateController.text = startDateIso;
    }
```

并把下文 3 处 `mondayStart` 引用改为 `startDateIso`（`updateConfig(startDateIso: ...)` 实参、SnackBar 文案 `'设置已保存（起始日期 $startDateIso）'`）。

- [ ] **Step 2: _buildDateField 按模式分支**

把 `_buildDateField()`（第 302-381 行）整体改为「分发器 + 通用模式单字段 + 学校模式原逻辑」：

```dart
  // ──── 子组件：日期字段 ────
  // 通用模式：单个简单日期选择；学校模式：周数推算/自动对齐周一（fr #2）
  Widget _buildDateField() {
    if (!_isSchoolMode) {
      return _buildGeneralDateField();
    }
    return _buildSchoolDateField();
  }

  /// 通用模式：只一个日期入口，点按弹系统日期选择器，选哪天存哪天。
  Widget _buildGeneralDateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () async {
            final current = DateTime.tryParse(_startDateController.text);
            final picked = await showDatePicker(
              context: context,
              initialDate: current ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2035),
              helpText: '选择开始日期',
            );
            if (picked == null) return;
            final iso = picked.toIso8601String().split('T')[0];
            setState(() => _startDateController.text = iso);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: zenCard(),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 18, color: ZenColors.secondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('起始日期', style: ZenText.label),
                      const SizedBox(height: 2),
                      Text(
                        _startDateController.text,
                        style: ZenText.body.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: ZenColors.secondary, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 学校模式：原「周数推算 / 选日期自动对齐周一」双入口逻辑。
  Widget _buildSchoolDateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () async {
            final date = await showDialog<String>(
              context: context,
              builder: (_) => const WeekCalculatorDialog(),
            );
            if (date != null) {
              setState(() => _startDateController.text = date);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: zenCard(),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 18, color: ZenColors.secondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('起始日期（周一）', style: ZenText.label),
                      const SizedBox(height: 2),
                      Text(
                        _startDateController.text,
                        style: ZenText.body.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: ZenColors.secondary, size: 18),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // 直接入口：选任意日期 → 自动回退到最近周一
        SizedBox(
          height: 40,
          child: OutlinedButton.icon(
            onPressed: () async {
              final current = DateTime.tryParse(_startDateController.text);
              final picked = await showDatePicker(
                context: context,
                initialDate: current ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2035),
                helpText: '选择开学日期或之前的任意一天',
              );
              if (picked == null) return;
              final monday = findNearestMondayOnOrBefore(picked);
              final iso = monday.toIso8601String().split('T')[0];
              // 只回填，不自动保存——与点卡片走 WeekCalculatorDialog 路径一致，
              // 避免整页被 pop、未保存的滑块改动被静默提交
              setState(() => _startDateController.text = iso);
            },
            style: zenButton(
              foreground: ZenColors.sage,
              border: ZenColors.hair,
            ).copyWith(
              minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
            icon: const Icon(Icons.calendar_today, size: 16, color: ZenColors.sage),
            label: Text(
              '选日期（自动对齐到最近周一）',
              style: ZenText.button.copyWith(color: ZenColors.sage),
            ),
          ),
        ),
      ],
    );
  }
```

（`WeekCalculatorDialog`/`findNearestMondayOnOrBefore` 仍被学校模式引用，import 保留。）

- [ ] **Step 3: analyze + 真机目视**

Run: `flutter analyze lib/core/timetable`
Expected: 0 issues。真机：进课表设置页切「通用模式」→ 开始日期区只一个入口，选任意日期（如周五）原样保存，SnackBar 显示所选日期、不弹回周一；切「学校模式」→ 原双入口/周一对齐行为不变。

## Task B3: commit + todo done（#2）

- [ ] **Step 1: commit + push**

```bash
git add lib/core/timetable/service/config/timetable_week_calculator.dart lib/core/timetable/service/config/timetable_settings_page.dart
git add -f test/core/timetable/start_date_resolver_test.dart
git commit -m "fix(timetable): 通用模式开始日期只留一个简单选择

#2: 新增 resolveStartDateIso(通用原样/学校回退周一), _buildDateField 按模式分支,
    通用模式单字段直弹 showDatePicker, 去掉周数推算与重复入口; 学校模式不动。
4 单测过, analyze 干净。kvcli fr #2."
git push
```

- [ ] **Step 2: 回填 todo**

```bash
kvcli todo done 2 --result "课表通用模式简化完成: resolveStartDateIso 纯函数(通用原样/学校回退周一) 4 单测过; 通用模式开始日期区只留单个日期选择, 去周数推算/重复入口/周一回退, 学校模式保留。analyze 干净。commit <hash>"
```

---

# Part C — clock 预设归零发声（#3）

**根因（已读码确认）：** `_startTimer`（`lab_clock_provider.dart:87-113`）每秒让 `remainingSeconds` 走负，**无归零检测、归零无声**。原生引擎无一次性播放 API，节拍器是连续引擎。

**修法（用户拍板：方案 A — just_audio 一次性音效）：** 仿 `PieceSound` 建 `ClockAlertSound` 单例播 `woodfish.wav`；抽 `crossedZero` 纯函数，在 `_startTimer` 每 tick 检测 `>0 → <=0` 跨零瞬间触发一次。

## Task C1: crossedZero 纯函数 + 单测

**Files:**
- Modify: `lib/lab/demos/clock/providers/lab_clock_provider.dart`（类内加静态纯函数）
- Test: `test/lab/clock_zero_sound_test.dart`（新建）

**Interfaces:**
- Produces: `LabClockProvider.crossedZero(int prev, int current) -> bool`

- [ ] **Step 1: 写失败测试**

```dart
// test/lab/clock_zero_sound_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/providers/lab_clock_provider.dart';

void main() {
  group('LabClockProvider.crossedZero', () {
    test('3 → 0 归零瞬间触发', () {
      expect(LabClockProvider.crossedZero(3, 0), isTrue);
    });
    test('1 → -2 跨过归零触发', () {
      expect(LabClockProvider.crossedZero(1, -2), isTrue);
    });
    test('已归零 0 → -1 不重复触发', () {
      expect(LabClockProvider.crossedZero(0, -1), isFalse);
    });
    test('负数持续 -5 → -6 不触发', () {
      expect(LabClockProvider.crossedZero(-5, -6), isFalse);
    });
    test('未归零 5 → 3 不触发', () {
      expect(LabClockProvider.crossedZero(5, 3), isFalse);
    });
  });
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `flutter test test/lab/clock_zero_sound_test.dart`
Expected: FAIL — `crossedZero` 未定义。

- [ ] **Step 3: 实现 crossedZero**

在 `lab_clock_provider.dart` 类内（`getRecordLiveDuration` 之后、`dispose` 之前）加：

```dart
  /// 归零检测纯函数：上一帧 >0 且 当前 <=0 → 触发一次提醒音。
  /// 只在该瞬间返回 true，避免剩余时间为负时每秒重复触发。fr #3。
  static bool crossedZero(int prev, int current) => prev > 0 && current <= 0;
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `flutter test test/lab/clock_zero_sound_test.dart`
Expected: PASS（5 用例）。

## Task C2: ClockAlertSound 一次性音效单例

**Files:**
- Create: `lib/lab/demos/clock/services/clock_alert_sound.dart`

**Interfaces:**
- Produces: `ClockAlertSound.instance.play() -> Future<void>`、`ClockAlertSound.instance.preload() -> Future<void>`（just_audio，播 `assets/audio/woodfish.wav`）

- [ ] **Step 1: 写实现（仿 PieceSound）**

```dart
// lib/lab/demos/clock/services/clock_alert_sound.dart
//
// clock 预设归零提醒音 —— just_audio 一次性音效单例（fr #3，方案 A）。
// 仿 PieceSound：单例 + 懒加载缓存就绪 Future + seek(0)+play 可快速重播。
// asset = assets/audio/woodfish.wav（clock 主题音，零新增资产；后续可换专属提示音）。

import 'package:just_audio/just_audio.dart';

class ClockAlertSound {
  ClockAlertSound._();
  static final ClockAlertSound instance = ClockAlertSound._();

  static const String _assetPath = 'assets/audio/woodfish.wav';

  final AudioPlayer _player = AudioPlayer();
  // 缓存的「就绪 Future」。null 表示尚未加载或上次加载失败（下次重试）。
  Future<void>? _ready;

  /// 可在 ClockDemo 打开时调用以消除首次归零的加载延迟；不调用也无妨。
  Future<void> preload() => _ensureReady();

  Future<void> _ensureReady() {
    return _ready ??= () async {
      try {
        await _player.setAsset(_assetPath);
      } catch (_) {
        _ready = null;
      }
    }();
  }

  /// 播放一次归零提醒音。fire-and-forget，调用方无需 await。
  Future<void> play() async {
    await _ensureReady();
    try {
      await _player.seek(Duration.zero);
      await _player.play();
    } catch (_) {
      // 播放失败不影响倒计时主流程。
    }
  }
}
```

- [ ] **Step 2: analyze**

Run: `flutter analyze lib/lab/demos/clock/services/clock_alert_sound.dart`
Expected: 0 issues。

## Task C3: _startTimer 接入归零检测

**Files:**
- Modify: `lib/lab/demos/clock/providers/lab_clock_provider.dart`（顶部 import + `_startTimer` 循环内）

**Interfaces:**
- Consumes: `crossedZero`（C1）、`ClockAlertSound.instance`（C2）

- [ ] **Step 1: import**

`lab_clock_provider.dart` import 区（`beat_coordinator.dart` 之后）加：

```dart
import '../services/clock_alert_sound.dart';
```

- [ ] **Step 2: _startTimer 循环内加归零检测**

`_startTimer`（第 88-112 行）的 for 循环内，在

```dart
          final elapsed = DateTime.now().difference(clock.startTime!).inSeconds;
          final newRemaining = baseSeconds - elapsed;

          if (newRemaining != clock.remainingSeconds) {
```

与 `if` 块之间插入归零检测（用循环顶部捕获的上一帧值）：

```dart
          final elapsed = DateTime.now().difference(clock.startTime!).inSeconds;
          final newRemaining = baseSeconds - elapsed;
          // 上一帧剩余 >0 → 当前 <=0：归零瞬间触发一次提醒音（fr #3）
          final prevRemaining = clock.remainingSeconds;

          if (newRemaining != clock.remainingSeconds) {
            if (crossedZero(prevRemaining, newRemaining)) {
              ClockAlertSound.instance.play();
            }
```

> 说明：`prevRemaining` 就是 `clock.remainingSeconds` 更新前的值（本轮尚未写入 `_clocks[i]`），`crossedZero` 保证只在跨零瞬间返回 true；负数持续不重复响。app 被 kill 后重开由 `_recalculateRunningClocks` 直接落到负值，不触发——避免开 app 时对早已过期的钟爆炸式响一声。

- [ ] **Step 3: analyze + 单测**

Run: `flutter analyze lib/lab/demos/clock && flutter test test/lab/clock_zero_sound_test.dart`
Expected: analyze 0 issues；test PASS。

- [ ] **Step 4: 真机听感（交给用户）**

冷启动直进 clock demo → 新建一个倒计时钟（如 10 秒）→ 开始：到 0 的瞬间应响一声木鱼，之后不再连响；若 clock 配了 bpm 正在走 beat，归零时提醒音不抢占/不打断节拍（节拍行为保持原样，本任务不改）。

## Task C4: commit + todo done（#3）

- [ ] **Step 1: commit + push**

```bash
git add lib/lab/demos/clock/services/clock_alert_sound.dart lib/lab/demos/clock/providers/lab_clock_provider.dart
git add -f test/lab/clock_zero_sound_test.dart
git commit -m "feat(clock): 预设归零触发一次性木鱼提醒音

#3: 新增 ClockAlertSound just_audio 单例(woodfish.wav, 仿 PieceSound),
    _startTimer 用 crossedZero 检测 >0→<=0 跨零瞬间播放一次。
5 单测过(crossedZero), analyze 干净。kvcli fr #3."
git push
```

- [ ] **Step 2: 回填 todo**

```bash
kvcli todo done 3 --result "clock 预设归零发声完成(方案A): ClockAlertSound just_audio 单例播 woodfish.wav, _startTimer 用 crossedZero 纯函数检测跨零瞬间触发一次, 负值不重复响。5 单测过, analyze 干净。需真机听感。commit <hash>"
```

---

## Self-Review

- **Spec 覆盖**：意图文档 4 簇 → Part D(#4)/A(#1)/B(#2)/C(#3) 全覆盖。D=定点改数字（用户拍板）、A=分钟显示+陶土默认色（用户拍板）、B=通用模式单日期选择+学校保留（用户拍板）、C=just_audio 一次性音效（用户拍板方案 A）。
- **占位符扫描**：所有代码步骤均含实际内容；无「TBD/类似 Task N/以实际为准」。A1 为纯显示表达式替换、C2 为纯新建文件，已说明其验证方式（analyze+目视 / analyze），非占位。
- **类型一致**：`AppText.titleSans/displaySans`（D1-D2）、`formatRecordDate`（A1）、`LabClockProvider.kDefaultClockColor/resolveColor`（A2）、`resolveStartDateIso`（B1-B2）、`LabClockProvider.crossedZero`/`ClockAlertSound.instance.play()`（C1-C3）命名跨任务一致。
- **测试覆盖**：D1(3)、A2(3)、B1(4)、C1(5) 均为纯函数/样式单测，不碰 FFI/原生/网络；测试文件均按 [[test_gitignore_force_add]] 用 `git add -f` 跟踪。
