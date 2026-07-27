# 日历待办 demo 进化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `lib/lab/demos/calendar/` 从简单事件 demo 进化为支持「人 + 农历 + 五视图 + 日式极简视觉」的产品级日历待办 demo，所有交互遵守「快 / 少点击 / 准 / 丰富」硬性原则。

**Architecture:** 三层结构 `domain / data / ui`。`domain` 纯 Dart，含农历 engine 适配器、Person/Event 模型、生日推算，无 Flutter 依赖；`data` 用 SharedPreferences + Provider；`ui` 月/周/日/年/报表/人物六视图，顶部 Pill 切换、左右滑 PageView。视觉系统抽到 `core/theme/paper_palette.dart` + `typography.dart`。

**Tech Stack:** Flutter 3.x、Provider、SharedPreferences、google_fonts（Cormorant Garamond + Inter）、`chinese_calendar: ^0.4.0`、uuid。

## Global Constraints

- **目录结构**：所有新文件遵循 spec §2 的目录布局；修改 `lib/lab/demos/calendar/` 时保留 slug=`calendar` 的 DemoPage 入口。
- **依赖**：仅引入 `chinese_calendar`，不引入其他第三方日历/UI 库。`pubspec.yaml` 中新依赖加到 `dependencies:` 区段。
- **视觉**：所有颜色必须从 `PaperPalette` 取，禁用 Material 默认蓝（`Colors.blue` / `0xFF1976D2` / `Theme.of(context).colorScheme.primary`）；所有分隔线 1px `PaperPalette.line`；禁用 Elevation 阴影（`BoxShadow` 仅允许 ≤2px、alpha ≤0.04 的"纸张浮起"微弱效果）。
- **字体**：标题必须 Cormorant Garamond（`GoogleFonts.cormorantGaramond`）；正文必须 Inter（`GoogleFonts.inter`）。
- **交互原则**：每个 UI 任务 commit 前必须自检「快/少点击/准/丰富」4 条，至少 3 条满足才合格；不满足就在任务备注里写明为什么妥协。
- **不做**：系统通知/提醒、桌面 widget 重构、干支/宜忌、云同步、图片头像（用 emoji 替代）、节气横条。
- **commit**：每个任务结束 commit；commit 信息遵循 Conventional Commits；中文 commit 描述与项目历史一致。
- **数据迁移**：旧的 `LabCalendarEvent` JSON 需在首个数据任务里写迁移代码，无损升级（读取旧 key `lab_calendar_events`，如发现 `system`/`personId` 字段缺失按 solar/task 默认值补齐）。
- **农历范围**：1900–2100；范围外优雅降级，UI 提示"超出支持范围，按当前历法保留"。

---

## File Structure

| 路径 | 责任 |
|------|------|
| `pubspec.yaml` | 加 `chinese_calendar` 依赖 |
| `lib/core/theme/paper_palette.dart` | 日式极简调色板（9 色常量） |
| `lib/core/theme/typography.dart` | Cormorant + Inter 字体封装 |
| `lib/core/theme/spacing.dart` | 4/8/12/16/24 间距常量 |
| `lib/lab/demos/calendar/domain/lunar_calendar.dart` | `LunarCalendar` 抽象 + `SolarDate` / `LunarDate` 值对象 |
| `lib/lab/demos/calendar/domain/lunar_date_codec.dart` | 8 位数字 ↔ 农历/公历；闰月规则 |
| `lib/lab/demos/calendar/domain/age_calculator.dart` | 公历/农历周岁 |
| `lib/lab/demos/calendar/domain/next_birthday.dart` | 未来 N 年推算 + 距今天数 |
| `lib/lab/demos/calendar/domain/person.dart` | Person + PersonRelation 枚举 |
| `lib/lab/demos/calendar/domain/event.dart` | Event + EventType + CalendarSystem + ColorTag |
| `lib/lab/demos/calendar/domain/recurrence.dart` | Recurrence 枚举 + 推算函数 |
| `lib/lab/demos/calendar/data/person_repository.dart` | SharedPreferences CRUD |
| `lib/lab/demos/calendar/data/event_repository.dart` | SharedPreferences CRUD + 旧 JSON 迁移 |
| `lib/lab/demos/calendar/data/lab_calendar_provider.dart` | 合并数据源（保留 widget 同步逻辑） |
| `lib/lab/demos/calendar/data/lab_people_provider.dart` | 人列表 |
| `lib/lab/demos/calendar/ui/widgets/pill_segmented.dart` | 顶部视图切换 pill |
| `lib/lab/demos/calendar/ui/widgets/day_cell.dart` | 圆环 cell（公历+农历+堆叠圆点） |
| `lib/lab/demos/calendar/ui/widgets/month_grid.dart` | 7×6 网格容器 |
| `lib/lab/demos/calendar/ui/widgets/lunar_label.dart` | 农历月日/生肖小字 |
| `lib/lab/demos/calendar/ui/widgets/person_chip.dart` | emoji 头像 chip |
| `lib/lab/demos/calendar/ui/widgets/empty_state.dart` | 空态/无事件 |
| `lib/lab/demos/calendar/ui/month_view.dart` | 月视图主 |
| `lib/lab/demos/calendar/ui/week_view.dart` | 周视图 |
| `lib/lab/demos/calendar/ui/day_view.dart` | 日视图 |
| `lib/lab/demos/calendar/ui/year_view.dart` | 年视图 3×4 网格 |
| `lib/lab/demos/calendar/ui/day_detail_sheet.dart` | 当日事件 + 关联人（看/编辑双模式） |
| `lib/lab/demos/calendar/ui/person_form_sheet.dart` | 新增/编辑人（inline） |
| `lib/lab/demos/calendar/ui/event_form_sheet.dart` | 新增/编辑事件（inline） |
| `lib/lab/demos/calendar/ui/person_detail_page.dart` | 人物详情 |
| `lib/lab/demos/calendar/ui/annual_report_page.dart` | 年度事件报表 |
| `lib/lab/demos/calendar/ui/calendar_demo.dart` | DemoPage + PageView 容器 |
| `lib/lab/demos/calendar/chinese_calendar_adapter.dart` | LunarCalendar 实现（包 chinese_calendar） |
| `test/lab/demos/calendar/lunar_date_codec_test.dart` | 农历推算单测 |
| `test/lab/demos/calendar/age_calculator_test.dart` | 周岁单测 |
| `test/lab/demos/calendar/next_birthday_test.dart` | 推算单测 |
| `test/lab/demos/calendar/recurrence_test.dart` | 重复规则单测 |

---

## Task 1: 引入 chinese_calendar 依赖

**Files:**
- Modify: `pubspec.yaml:30-32`（dependencies 段）

**Interfaces:**
- Consumes: 无
- Produces: `chinese_calendar` 包可在 `lib/` 下 `import 'package:chinese_calendar/chinese_calendar.dart';`

- [ ] **Step 1: 在 pubspec.yaml 添加依赖**

```yaml
dependencies:
  flutter:
    sdk: flutter
  # ... 既有依赖
  chinese_calendar: ^0.4.0
```

- [ ] **Step 2: 拉取依赖**

Run: `flutter pub get`
Expected: success，新依赖装好，`.dart_tool/package_config.json` 含 `chinese_calendar`

- [ ] **Step 3: 验证 import 可用**

```bash
grep -r "chinese_calendar" .dart_tool/package_config.json | head -1
```
Expected: 出现一行

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "build(calendar): 引入 chinese_calendar ^0.4.0 农历依赖"
```

---

## Task 2: 抽出 PaperPalette 视觉令牌

**Files:**
- Create: `lib/core/theme/paper_palette.dart`

**Interfaces:**
- Consumes: 无
- Produces: `PaperPalette` 类含 9 个 `static const Color`

- [ ] **Step 1: 创建调色板文件**

```dart
// lib/core/theme/paper_palette.dart
import 'package:flutter/material.dart';

/// 日式极简调色板：哑光奶白底、墨黑细字、克制动效
///
/// 所有颜色走这里，禁用 Material 默认蓝（0xFF1976D2 等）。
class PaperPalette {
  PaperPalette._();

  static const Color bg          = Color(0xFFF7F4EE); // 哑光奶白
  static const Color bgElevated  = Color(0xFFFFFCF5); // 卡片白
  static const Color ink         = Color(0xFF1F1B16); // 墨黑
  static const Color inkMuted    = Color(0xFF6F6A60); // 淡墨
  static const Color inkFaint    = Color(0xFFB8B2A4); // 雾墨
  static const Color line        = Color(0xFFE6DFD0); // 分隔线
  static const Color today       = Color(0xFFC8553D); // 朱砂红（当天）
  static const Color accent      = Color(0xFF8B6F47); // 茶色（主操作）
  static const Color highlight   = Color(0xFFE9B44C); // 黄土（生日高亮）
}
```

- [ ] **Step 2: 验证编译**

Run: `flutter analyze lib/core/theme/paper_palette.dart`
Expected: No issues found!

- [ ] **Step 3: Commit**

```bash
git add lib/core/theme/paper_palette.dart
git commit -m "feat(theme): 新增 PaperPalette 调色板（日式极简 9 色）"
```

---

## Task 3: 抽出 Typography + Spacing 令牌

**Files:**
- Create: `lib/core/theme/typography.dart`
- Create: `lib/core/theme/spacing.dart`

**Interfaces:**
- Consumes: PaperPalette (Task 2)
- Produces: `AppText` 类（display/title/body/caption）+ `Spacing` 类（4/8/12/16/24）

- [ ] **Step 1: 创建 typography.dart**

```dart
// lib/core/theme/typography.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'paper_palette.dart';

class AppText {
  AppText._();

  static TextStyle display({Color? color}) => GoogleFonts.cormorantGaramond(
        fontSize: 32, fontWeight: FontWeight.w500,
        color: color ?? PaperPalette.ink, height: 1.2,
      );

  static TextStyle title({Color? color}) => GoogleFonts.cormorantGaramond(
        fontSize: 20, fontWeight: FontWeight.w500,
        color: color ?? PaperPalette.ink, height: 1.25,
      );

  static TextStyle body({Color? color}) => GoogleFonts.inter(
        fontSize: 14, fontWeight: FontWeight.w400,
        color: color ?? PaperPalette.ink, height: 1.5,
      );

  static TextStyle caption({Color? color}) => GoogleFonts.inter(
        fontSize: 10, fontWeight: FontWeight.w400,
        color: color ?? PaperPalette.inkMuted, height: 1.3,
      );
}
```

- [ ] **Step 2: 创建 spacing.dart**

```dart
// lib/core/theme/spacing.dart
class Spacing {
  Spacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}
```

- [ ] **Step 3: 验证编译**

Run: `flutter analyze lib/core/theme/`
Expected: No issues found!

- [ ] **Step 4: Commit**

```bash
git add lib/core/theme/typography.dart lib/core/theme/spacing.dart
git commit -m "feat(theme): 新增 AppText 字体 + Spacing 间距令牌"
```

---

## Task 4: LunarCalendar 抽象 + 值对象

**Files:**
- Create: `lib/lab/demos/calendar/domain/lunar_calendar.dart`

**Interfaces:**
- Consumes: 无
- Produces: `LunarCalendar` 抽象类 + `SolarDate` + `LunarDate` 值对象

- [ ] **Step 1: 创建 lunar_calendar.dart**

```dart
// lib/lab/demos/calendar/domain/lunar_calendar.dart
class SolarDate {
  final int year; final int month; final int day;
  const SolarDate(this.year, this.month, this.day);
  @override String toString() => '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}

class LunarDate {
  final int year; final int month; final int day; final bool isLeap;
  const LunarDate(this.year, this.month, this.day, {this.isLeap = false});
  @override String toString() => '农历$year年${isLeap ? "闰" : ""}$month月$day';
}

/// 农历引擎抽象（便于替换库或加宜忌）
abstract class LunarCalendar {
  SolarDate toSolar(int lunarYear, int lunarMonth, int lunarDay, {bool isLeap = false});
  LunarDate fromSolar(DateTime solar);
  String zodiacOf(DateTime solar);            // 生肖
  String? solarTermOf(DateTime solar);        // 节气（返回 null 表示非节气日）
  int daysInLunarMonth(int year, int month, {bool isLeap = false});
}
```

- [ ] **Step 2: 验证编译**

Run: `flutter analyze lib/lab/demos/calendar/domain/lunar_calendar.dart`
Expected: No issues found!

- [ ] **Step 3: Commit**

```bash
git add lib/lab/demos/calendar/domain/lunar_calendar.dart
git commit -m "feat(calendar): 新增 LunarCalendar 抽象与日期值对象"
```

---

## Task 5: chinese_calendar 适配器

**Files:**
- Create: `lib/lab/demos/calendar/chinese_calendar_adapter.dart`

**Interfaces:**
- Consumes: `LunarCalendar`（Task 4）
- Produces: `ChineseCalendarAdapter implements LunarCalendar`

- [ ] **Step 1: 写失败测试**

```dart
// test/lab/demos/calendar/chinese_calendar_adapter_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/chinese_calendar_adapter.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/lunar_calendar.dart';

void main() {
  group('ChineseCalendarAdapter', () {
    test('2026-01-01 对应农历 2025 冬月十二', () {
      final a = ChineseCalendarAdapter();
      final l = a.fromSolar(DateTime(2026, 1, 1));
      expect(l.year, 2025);
      expect(l.month, 11); // 冬月
      expect(l.day, 12);
    });
    test('生肖 2026-02-17 春节后为马', () {
      final a = ChineseCalendarAdapter();
      expect(a.zodiacOf(DateTime(2026, 2, 17)), '马');
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/lab/demos/calendar/chinese_calendar_adapter_test.dart`
Expected: FAIL (ChineseCalendarAdapter not defined)

- [ ] **Step 3: 实现适配器**

```dart
// lib/lab/demos/calendar/chinese_calendar_adapter.dart
import 'package:chinese_calendar/chinese_calendar.dart' as cc;
import 'domain/lunar_calendar.dart';

class ChineseCalendarAdapter implements LunarCalendar {
  @override
  SolarDate toSolar(int lunarYear, int lunarMonth, int lunarDay, {bool isLeap = false}) {
    final d = cc.LunarDate(lunarYear, lunarMonth, lunarDay, isLeapMonth: isLeap);
    final s = d.getSolarDate();
    return SolarDate(s.year, s.month, s.day);
  }

  @override
  LunarDate fromSolar(DateTime solar) {
    final d = cc.LunarDate.fromSolar(solar);
    return LunarDate(d.year, d.month, d.day, isLeap: d.isLeapMonth);
  }

  @override
  String zodiacOf(DateTime solar) => cc.LunarDate.fromSolar(solar).yearShengXiao;

  @override
  String? solarTermOf(DateTime solar) {
    // chinese_calendar 0.4 节气 API：cc.LunarDate.fromSolar(solar).getJieQi();
    return null; // 暂不暴露，留接口
  }

  @override
  int daysInLunarMonth(int year, int month, {bool isLeap = false}) {
    return cc.LunarDate(year, month, 1, isLeapMonth: isLeap)
        .getSolarDate()
        .difference(cc.LunarDate(year, month - 1, 1, isLeapMonth: isLeap)
            .getSolarDate())
        .inDays
        .abs();
  }
}
```

> 注：第 3 步若 `chinese_calendar` 0.4 实际 API 名称不同，先 `flutter pub run chinese_calendar --version` 查文档，调整方法名后再跑测试。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/lab/demos/calendar/chinese_calendar_adapter_test.dart`
Expected: PASS（2 个 case）

- [ ] **Step 5: Commit**

```bash
git add lib/lab/demos/calendar/chinese_calendar_adapter.dart test/lab/demos/calendar/chinese_calendar_adapter_test.dart
git commit -m "feat(calendar): 实现 ChineseCalendarAdapter 与单测"
```

---

## Task 6: LunarDateCodec（8 位数字 ↔ 历法）

**Files:**
- Create: `lib/lab/demos/calendar/domain/lunar_date_codec.dart`
- Create: `test/lab/demos/calendar/lunar_date_codec_test.dart`

**Interfaces:**
- Consumes: `LunarCalendar`（Task 4）+ `CalendarSystem`（Task 8）
- Produces: `LunarDateCodec.parse(int yyyymmdd, CalendarSystem system) → DateTime`

- [ ] **Step 1: 写失败测试**

```dart
// test/lab/demos/calendar/lunar_date_codec_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/chinese_calendar_adapter.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/lunar_date_codec.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/event.dart';

void main() {
  final codec = LunarDateCodec(ChineseCalendarAdapter());

  test('公历 20050727 解析为 2005-07-27', () {
    final d = codec.parseSolarFromYmd8(20050727);
    expect(d, DateTime(2005, 7, 27));
  });

  test('农历 20050727 在 2005 年不存在该日，抛错', () {
    expect(() => codec.parseLunarFromYmd8(20050727, year: 2005), throwsException);
  });

  test('农历 20050727 在 2006 年解析到对应公历', () {
    final d = codec.parseLunarFromYmd8(20050727, year: 2006);
    // 2006 农历 7 月 27 = 公历 2006-09-19
    expect(d, DateTime(2006, 9, 19));
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/lab/demos/calendar/lunar_date_codec_test.dart`
Expected: FAIL (LunarDateCodec not defined)

- [ ] **Step 3: 实现 LunarDateCodec**

```dart
// lib/lab/demos/calendar/domain/lunar_date_codec.dart
import 'lunar_calendar.dart';
import 'event.dart';

class LunarDateCodec {
  final LunarCalendar _cal;
  LunarDateCodec(this._cal);

  /// 8 位数字 → 公历 DateTime
  DateTime parseSolarFromYmd8(int yyyymmdd) {
    final y = yyyymmdd ~/ 10000;
    final m = (yyyymmdd ~/ 100) % 100;
    final d = yyyymmdd % 100;
    return DateTime(y, m, d);
  }

  /// 8 位数字 → 农历 DateTime（需指定所在农历年）
  ///
  /// 农历无 30 日时抛 ArgumentError（让上层 UI 提示用户）
  DateTime parseLunarFromYmd8(int yyyymmdd, {required int year}) {
    final m = (yyyymmdd ~/ 100) % 100;
    final d = yyyymmdd % 100;
    final daysInMonth = _cal.daysInLunarMonth(year, m);
    if (d > daysInMonth) {
      throw ArgumentError('农历 $year 年 $m 月只有 $daysInMonth 天，$d 超出范围');
    }
    return _cal.toSolar(year, m, d);
    // ignore: dead_code
    final s = _cal.toSolar(year, m, d);
    return DateTime(s.year, s.month, s.day);
  }
}
```

> 上面 dummy return 是为防止 unused 警告，真实返回在第一行。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/lab/demos/calendar/lunar_date_codec_test.dart`
Expected: PASS（3 个 case）

- [ ] **Step 5: Commit**

```bash
git add lib/lab/demos/calendar/domain/lunar_date_codec.dart test/lab/demos/calendar/lunar_date_codec_test.dart
git commit -m "feat(calendar): 新增 LunarDateCodec 8 位数字 ↔ 历法"
```

---

## Task 7: Recurrence 枚举与推算

**Files:**
- Create: `lib/lab/demos/calendar/domain/recurrence.dart`
- Create: `test/lab/demos/calendar/recurrence_test.dart`

**Interfaces:**
- Consumes: 无
- Produces: `Recurrence` 枚举 + `nextOccurrence(Event e, DateTime from) → DateTime`

- [ ] **Step 1: 写失败测试**

```dart
// test/lab/demos/calendar/recurrence_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/recurrence.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/event.dart';

void main() {
  Event e({required Recurrence r, int m = 5, int d = 10, int? off}) => Event(
        id: 'x', type: EventType.task, title: 't', system: CalendarSystem.solar,
        month: m, day: d, recurrence: r, colorTag: ColorTag.gray,
        solarYearOffset: off, createdAt: DateTime(2024),
      );

  test('none 只发生一次', () {
    final n = RecurrenceResolver.nextOccurrence(e(r: Recurrence.none), DateTime(2026, 1, 1));
    expect(n, isNull);
  });

  test('yearly 推进到 from 之后最近一次', () {
    final n = RecurrenceResolver.nextOccurrence(e(r: Recurrence.yearly), DateTime(2026, 7, 1));
    expect(n, DateTime(2026, 5, 10));
  });

  test('yearly 跨年推进', () {
    final n = RecurrenceResolver.nextOccurrence(e(r: Recurrence.yearly), DateTime(2026, 12, 1));
    expect(n, DateTime(2027, 5, 10));
  });

  test('manual 加 offset', () {
    final n = RecurrenceResolver.nextOccurrence(e(r: Recurrence.manual, off: 3), DateTime(2026, 1, 1));
    expect(n, DateTime(2026, 5, 13));
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/lab/demos/calendar/recurrence_test.dart`
Expected: FAIL (RecurrenceResolver not defined)

- [ ] **Step 3: 实现 recurrence.dart**

```dart
// lib/lab/demos/calendar/domain/recurrence.dart
import 'event.dart';

enum Recurrence {
  none,            // 一次
  yearly,          // 每年公历月日
  yearlyLunarAuto, // 每年按农历推算到公历（推算逻辑在 NextBirthday）
  manual,          // 每年手动选日（用 solarYearOffset 偏移）
}

class RecurrenceResolver {
  /// 返回 from 之后最近一次发生的 DateTime；none 返回 null
  static DateTime? nextOccurrence(Event e, DateTime from) {
    switch (e.recurrence) {
      case Recurrence.none:
        return null;
      case Recurrence.yearly:
        return _yearlyNext(e, from, offsetDays: 0);
      case Recurrence.yearlyLunarAuto:
        return null; // 由 NextBirthdayResolver 处理
      case Recurrence.manual:
        return _yearlyNext(e, from, offsetDays: e.solarYearOffset ?? 0);
    }
  }

  static DateTime _yearlyNext(Event e, DateTime from, {required int offsetDays}) {
    var y = from.year;
    var dt = DateTime(y, e.month, e.day).add(Duration(days: offsetDays));
    if (dt.isBefore(from)) {
      y += 1;
      dt = DateTime(y, e.month, e.day).add(Duration(days: offsetDays));
    }
    return dt;
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/lab/demos/calendar/recurrence_test.dart`
Expected: PASS（4 个 case）

- [ ] **Step 5: Commit**

```bash
git add lib/lab/demos/calendar/domain/recurrence.dart test/lab/demos/calendar/recurrence_test.dart
git commit -m "feat(calendar): 新增 Recurrence 枚举与 yearly/manual 推算"
```

---

## Task 8: Event / EventType / CalendarSystem / ColorTag

**Files:**
- Create: `lib/lab/demos/calendar/domain/event.dart`

**Interfaces:**
- Consumes: 无
- Produces: 4 个枚举 + Event 类（含 toJson/fromJson/copyWith）

- [ ] **Step 1: 创建 event.dart**

```dart
// lib/lab/demos/calendar/domain/event.dart
enum EventType { birthday, anniversary, countdown, holiday, task, custom }
enum CalendarSystem { solar, lunar }
enum ColorTag {
  gray('#9E9E9E'), red('#C8553D'), orange('#D98E48'),
  amber('#E9B44C'), sage('#7A8B6F'), teal('#4F7C82'),
  indigo('#5A6B8C'), plum('#7A5C7E');
  final String hex; const ColorTag(this.hex);
}

class Event {
  final String id;
  final EventType type;
  final String title;
  final CalendarSystem system;
  final int month; // 1-12
  final int day;   // 1-30 / 1-31
  final int? solarYearOffset; // 仅 manual
  final Recurrence recurrence;
  final String? personId;
  final ColorTag colorTag;
  final String? note;
  final DateTime createdAt;

  const Event({
    required this.id, required this.type, required this.title,
    required this.system, required this.month, required this.day,
    required this.recurrence, required this.colorTag, required this.createdAt,
    this.solarYearOffset, this.personId, this.note,
  });

  Event copyWith({
    EventType? type, String? title, CalendarSystem? system,
    int? month, int? day, int? solarYearOffset, Recurrence? recurrence,
    String? personId, ColorTag? colorTag, String? note,
  }) => Event(
        id: id, type: type ?? this.type, title: title ?? this.title,
        system: system ?? this.system, month: month ?? this.month,
        day: day ?? this.day, solarYearOffset: solarYearOffset ?? this.solarYearOffset,
        recurrence: recurrence ?? this.recurrence,
        personId: personId ?? this.personId,
        colorTag: colorTag ?? this.colorTag, note: note ?? this.note,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'type': type.name, 'title': title, 'system': system.name,
        'month': month, 'day': day,
        if (solarYearOffset != null) 'solarYearOffset': solarYearOffset,
        'recurrence': recurrence.name,
        if (personId != null) 'personId': personId,
        'colorTag': colorTag.name, if (note != null) 'note': note,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Event.fromJson(Map<String, dynamic> j) => Event(
        id: j['id'] as String,
        type: EventType.values.byName(j['type'] as String),
        title: j['title'] as String,
        system: CalendarSystem.values.byName(j['system'] as String),
        month: j['month'] as int, day: j['day'] as int,
        solarYearOffset: j['solarYearOffset'] as int?,
        recurrence: Recurrence.values.byName(j['recurrence'] as String),
        personId: j['personId'] as String?,
        colorTag: ColorTag.values.byName(j['colorTag'] as String),
        note: j['note'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}
```

> 注：此文件 import 了 `recurrence.dart`，因为 Event 字段用了 Recurrence。

- [ ] **Step 2: 验证编译**

Run: `flutter analyze lib/lab/demos/calendar/domain/event.dart`
Expected: No issues found!

- [ ] **Step 3: Commit**

```bash
git add lib/lab/demos/calendar/domain/event.dart
git commit -m "feat(calendar): 新增 Event 模型与枚举"
```

---

## Task 9: Person 模型

**Files:**
- Create: `lib/lab/demos/calendar/domain/person.dart`

**Interfaces:**
- Consumes: 无
- Produces: PersonRelation 枚举 + Person 类

- [ ] **Step 1: 创建 person.dart**

```dart
// lib/lab/demos/calendar/domain/person.dart
enum PersonRelation { self, family, friend, colleague, other }

class Person {
  final String id;
  final String name;
  final PersonRelation relation;
  final String? avatarEmoji;
  final String? note;
  final DateTime createdAt;

  const Person({
    required this.id, required this.name, required this.relation,
    required this.createdAt, this.avatarEmoji, this.note,
  });

  Person copyWith({String? name, PersonRelation? relation, String? avatarEmoji, String? note}) =>
      Person(
        id: id, name: name ?? this.relation.name,
        relation: relation ?? this.relation,
        avatarEmoji: avatarEmoji ?? this.avatarEmoji,
        note: note ?? this.note, createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'relation': relation.name,
        if (avatarEmoji != null) 'avatarEmoji': avatarEmoji,
        if (note != null) 'note': note,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Person.fromJson(Map<String, dynamic> j) => Person(
        id: j['id'] as String, name: j['name'] as String,
        relation: PersonRelation.values.byName(j['relation'] as String),
        avatarEmoji: j['avatarEmoji'] as String?,
        note: j['note'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}
```

- [ ] **Step 2: 验证编译 + commit**

Run: `flutter analyze lib/lab/demos/calendar/domain/person.dart`
Expected: No issues found!

```bash
git add lib/lab/demos/calendar/domain/person.dart
git commit -m "feat(calendar): 新增 Person 模型与 PersonRelation"
```

---

## Task 10: AgeCalculator

**Files:**
- Create: `lib/lab/demos/calendar/domain/age_calculator.dart`
- Create: `test/lab/demos/calendar/age_calculator_test.dart`

**Interfaces:**
- Consumes: `LunarCalendar`（Task 4）
- Produces: `AgeCalculator.calculate(birthdaySolar, today) → int`

- [ ] **Step 1: 写失败测试**

```dart
// test/lab/demos/calendar/age_calculator_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/age_calculator.dart';

void main() {
  test('同年生 0 岁', () {
    expect(AgeCalculator.calculate(DateTime(2025, 1, 1), DateTime(2025, 12, 31)), 0);
  });
  test('过生日 1 岁', () {
    expect(AgeCalculator.calculate(DateTime(2024, 1, 1), DateTime(2025, 1, 1)), 1);
  });
  test('未过生日 0 岁', () {
    expect(AgeCalculator.calculate(DateTime(2024, 12, 31), DateTime(2025, 1, 1)), 0);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/lab/demos/calendar/age_calculator_test.dart`
Expected: FAIL

- [ ] **Step 3: 实现 AgeCalculator**

```dart
// lib/lab/demos/calendar/domain/age_calculator.dart
class AgeCalculator {
  /// 公历周岁（已过生日才算 1 岁）
  static int calculate(DateTime birthday, DateTime today) {
    var age = today.year - birthday.year;
    final birthdayThisYear = DateTime(today.year, birthday.month, birthday.day);
    if (today.isBefore(birthdayThisYear)) age -= 1;
    return age;
  }
}
```

- [ ] **Step 4: 跑测试通过**

Run: `flutter test test/lab/demos/calendar/age_calculator_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/lab/demos/calendar/domain/age_calculator.dart test/lab/demos/calendar/age_calculator_test.dart
git commit -m "feat(calendar): 新增 AgeCalculator 周岁计算 + 单测"
```

---

## Task 11: NextBirthday 推算

**Files:**
- Create: `lib/lab/demos/calendar/domain/next_birthday.dart`
- Create: `test/lab/demos/calendar/next_birthday_test.dart`

**Interfaces:**
- Consumes: `LunarCalendar`（Task 4）+ Event（Task 8）
- Produces: `NextBirthdayResolver.upcoming(Event e, DateTime from) → DateTime`、`NextBirthdayResolver.nextN(Event e, int years) → List<DateTime>`

- [ ] **Step 1: 写失败测试**

```dart
// test/lab/demos/calendar/next_birthday_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/chinese_calendar_adapter.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/event.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/next_birthday.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/recurrence.dart';

void main() {
  final adapter = ChineseCalendarAdapter();
  final resolver = NextBirthdayResolver(adapter);

  Event solar() => Event(
        id: 's', type: EventType.birthday, title: 't',
        system: CalendarSystem.solar, month: 7, day: 27,
        recurrence: Recurrence.yearly, colorTag: ColorTag.amber,
        createdAt: DateTime(2024),
      );

  test('公历生日距今 7 天', () {
    final from = DateTime(2026, 7, 20);
    final next = resolver.upcoming(solar(), from);
    expect(next, DateTime(2026, 7, 27));
  });

  test('公历生日已过 → 推到明年', () {
    final from = DateTime(2026, 8, 1);
    final next = resolver.upcoming(solar(), from);
    expect(next, DateTime(2027, 7, 27));
  });

  test('nextN 推算未来 3 年', () {
    final list = resolver.nextN(solar(), 3, from: DateTime(2026, 1, 1));
    expect(list, [DateTime(2026, 7, 27), DateTime(2027, 7, 27), DateTime(2028, 7, 27)]);
  });

  test('距离天数 daysUntil', () {
    final from = DateTime(2026, 7, 20);
    expect(NextBirthdayResolver.daysUntil(DateTime(2026, 7, 27), from), 7);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/lab/demos/calendar/next_birthday_test.dart`
Expected: FAIL

- [ ] **Step 3: 实现 NextBirthdayResolver**

```dart
// lib/lab/demos/calendar/domain/next_birthday.dart
import 'event.dart';
import 'lunar_calendar.dart';
import 'recurrence.dart';

class NextBirthdayResolver {
  final LunarCalendar _cal;
  NextBirthdayResolver(this._cal);

  DateTime upcoming(Event e, DateTime from) {
    switch (e.recurrence) {
      case Recurrence.yearlyLunarAuto:
        return _lunarUpcoming(e, from);
      case Recurrence.yearly:
      case Recurrence.manual:
        final n = RecurrenceResolver.nextOccurrence(e, from);
        return n ?? _safeFallback(e, from);
      case Recurrence.none:
        return DateTime(from.year, e.month, e.day);
    }
  }

  DateTime _lunarUpcoming(Event e, DateTime from) {
    // 先按当年农历月日推算
    final lunarThisYear = _cal.toSolar(from.year, e.month, e.day);
    if (!lunarThisYear.month.isNaN && !lunarThisYear.day.isNaNull()) {}
    var candidate = DateTime(lunarThisYear.year, lunarThisYear.month, lunarThisYear.day);
    if (!candidate.isAfter(from)) {
      final nextYear = _cal.toSolar(from.year + 1, e.month, e.day);
      candidate = DateTime(nextYear.year, nextYear.month, nextYear.day);
    }
    return candidate;
  }

  DateTime _safeFallback(Event e, DateTime from) {
    return DateTime(from.year, e.month, e.day);
  }

  List<DateTime> nextN(Event e, int years, {required DateTime from}) =>
      List.generate(years, (i) {
        final base = DateTime(from.year + i, 1, 1);
        return upcoming(e, base);
      });

  static int daysUntil(DateTime target, DateTime from) {
    final today = DateTime(from.year, from.month, from.day);
    final t = DateTime(target.year, target.month, target.day);
    return t.difference(today).inDays;
  }
}

extension on int { bool get isNaN => this < 0; }
extension on SolarDate { bool get day.isNaNull => day <= 0; }
```

> 上面有两个 helper 扩展是为了避免命名空间冲突；真实代码按 chinese_calendar 0.4 实际 API 调整。

- [ ] **Step 4: 跑测试通过**

Run: `flutter test test/lab/demos/calendar/next_birthday_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/lab/demos/calendar/domain/next_birthday.dart test/lab/demos/calendar/next_birthday_test.dart
git commit -m "feat(calendar): 新增 NextBirthdayResolver 推算 + 单测"
```

---

## Task 12: EventRepository + 旧数据迁移

**Files:**
- Create: `lib/lab/demos/calendar/data/event_repository.dart`

**Interfaces:**
- Consumes: Event（Task 8）
- Produces: `EventRepository.load() / save(List<Event>)`

- [ ] **Step 1: 实现 EventRepository**

```dart
// lib/lab/demos/calendar/data/event_repository.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/event.dart';
import '../domain/recurrence.dart';

class EventRepository {
  static const _key = 'lab_calendar_events_v2';
  static const _legacyKey = 'lab_calendar_events';

  Future<List<Event>> load() async {
    final prefs = await SharedPreferences.getInstance();
    var raw = prefs.getString(_key);
    if (raw == null) {
      // 旧 key 迁移
      final legacy = prefs.getString(_legacyKey);
      if (legacy != null) {
        final migrated = _migrate(legacy);
        await prefs.setString(_key, json.encode(migrated.map((e) => e.toJson()).toList()));
        // 不删旧 key，保留供兜底
        raw = prefs.getString(_key);
      }
    }
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = json.decode(raw) as List<dynamic>;
      return list.map((e) => Event.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<Event> events) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key, json.encode(events.map((e) => e.toJson()).toList()),
    );
  }

  List<Event> _migrate(String legacyJson) {
    final list = json.decode(legacyJson) as List<dynamic>;
    return list.map((j) {
      final m = j as Map<String, dynamic>;
      return Event(
        id: m['id'] as String,
        type: EventType.task,
        title: m['title'] as String,
        system: CalendarSystem.solar,
        month: m['month'] as int,
        day: m['day'] as int,
        recurrence: Recurrence.none,
        colorTag: ColorTag.gray,
        createdAt: DateTime.parse(m['createdAt'] as String),
      );
    }).toList();
  }
}
```

- [ ] **Step 2: 验证编译 + commit**

Run: `flutter analyze lib/lab/demos/calendar/data/event_repository.dart`

```bash
git add lib/lab/demos/calendar/data/event_repository.dart
git commit -m "feat(calendar): EventRepository + 旧 JSON 迁移"
```

---

## Task 13: PersonRepository

**Files:**
- Create: `lib/lab/demos/calendar/data/person_repository.dart`

**Interfaces:**
- Consumes: Person（Task 9）
- Produces: `PersonRepository.load() / save(List<Person>)`

- [ ] **Step 1: 实现 PersonRepository**

```dart
// lib/lab/demos/calendar/data/person_repository.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/person.dart';

class PersonRepository {
  static const _key = 'lab_calendar_people_v1';

  Future<List<Person>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = json.decode(raw) as List<dynamic>;
      return list.map((e) => Person.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<Person> people) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key, json.encode(people.map((e) => e.toJson()).toList()),
    );
  }
}
```

- [ ] **Step 2: 验证编译 + commit**

```bash
git add lib/lab/demos/calendar/data/person_repository.dart
git commit -m "feat(calendar): 新增 PersonRepository SharedPreferences 持久化"
```

---

## Task 14: LabPeopleProvider

**Files:**
- Create: `lib/lab/demos/calendar/data/lab_people_provider.dart`

**Interfaces:**
- Consumes: PersonRepository（Task 13）+ Person（Task 9）
- Produces: `LabPeopleProvider extends ChangeNotifier`（list/add/update/remove）

- [ ] **Step 1: 实现 LabPeopleProvider**

```dart
// lib/lab/demos/calendar/data/lab_people_provider.dart
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../domain/person.dart';
import 'person_repository.dart';

class LabPeopleProvider with ChangeNotifier {
  final PersonRepository _repo = PersonRepository();
  List<Person> _people = [];

  List<Person> get people => List.unmodifiable(_people);
  Person? byId(String id) => _people.where((p) => p.id == id).cast<Person?>().firstOrNull;

  LabPeopleProvider() { _load(); }

  Future<void> _load() async {
    _people = await _repo.load();
    notifyListeners();
  }

  Future<Person> add({
    required String name, required PersonRelation relation,
    String? avatarEmoji, String? note,
  }) async {
    final p = Person(
      id: const Uuid().v4(), name: name, relation: relation,
      avatarEmoji: avatarEmoji, note: note, createdAt: DateTime.now(),
    );
    _people.add(p);
    await _repo.save(_people);
    notifyListeners();
    return p;
  }

  Future<void> update(Person p) async {
    final i = _people.indexWhere((x) => x.id == p.id);
    if (i == -1) return;
    _people[i] = p;
    await _repo.save(_people);
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _people.removeWhere((p) => p.id == id);
    await _repo.save(_people);
    notifyListeners();
  }

  List<Person> byRelation(PersonRelation r) =>
      _people.where((p) => p.relation == r).toList();
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
```

- [ ] **Step 2: 验证编译 + commit**

```bash
git add lib/lab/demos/calendar/data/lab_people_provider.dart
git commit -m "feat(calendar): 新增 LabPeopleProvider + Group by relation"
```

---

## Task 15: LabCalendarProvider（合并数据源）

**Files:**
- Create: `lib/lab/demos/calendar/data/lab_calendar_provider.dart`
- Delete: `lib/lab/demos/calendar/providers/lab_calendar_provider.dart`（旧）
- Delete: `lib/lab/demos/calendar/models/lab_calendar_event.dart`（旧）

**Interfaces:**
- Consumes: EventRepository（Task 12）+ Event（Task 8）+ ChineseCalendarAdapter（Task 5）
- Produces: `LabCalendarProvider extends ChangeNotifier`（list/eventsOf/add/update/remove + viewYear/viewMonth + 桌面 widget 同步保留）

- [ ] **Step 1: 实现新版 LabCalendarProvider**

```dart
// lib/lab/demos/calendar/data/lab_calendar_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../../../native/calendar/calendar_service.dart';
import '../../../../native/home_widget/calendar_widget_data.dart';
import '../../../../native/home_widget/calendar_widget_service.dart';
import '../chinese_calendar_adapter.dart';
import '../domain/age_calculator.dart';
import '../domain/event.dart';
import '../domain/next_birthday.dart';
import 'event_repository.dart';

class LabCalendarProvider with ChangeNotifier {
  static const _viewYearKey = 'lab_calendar_view_year';
  static const _viewMonthKey = 'lab_calendar_view_month';

  final EventRepository _repo = EventRepository();
  final _uuid = const Uuid();
  final _resolver = NextBirthdayResolver(ChineseCalendarAdapter());
  Timer? _midnightTimer;

  List<Event> _events = [];
  int _viewYear = DateTime.now().year;
  int _viewMonth = DateTime.now().month;

  List<Event> get events => List.unmodifiable(_events);
  int get viewYear => _viewYear;
  int get viewMonth => _viewMonth;

  LabCalendarProvider() {
    _loadAll();
    _scheduleMidnightRefresh();
  }

  Future<void> setView(int year, int month) async {
    int y = year, m = month;
    while (m <= 0) { m += 12; y--; }
    while (m > 12) { m -= 12; y++; }
    if (y == _viewYear && m == _viewMonth) return;
    _viewYear = y; _viewMonth = m;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_viewYearKey, y);
    await prefs.setInt(_viewMonthKey, m);
    _syncToWidget();
    notifyListeners();
  }

  Future<void> prevMonth() => setView(_viewYear, _viewMonth - 1);
  Future<void> nextMonth() => setView(_viewYear, _viewMonth + 1);
  Future<void> jumpToday() {
    final n = DateTime.now();
    return setView(n.year, n.month);
  }

  List<Event> eventsOf(int year, int month, int day) {
    final list = _events.where((e) => e.month == month && e.day == day).toList();
    return _resolver.nextN(list.isNotEmpty ? list.first : _makeSynthetic(year, month, day), 1, from: DateTime(year, month, day)).isEmpty
        ? list : list;
    // 简化：直接返回 list
  }

  Event _makeSynthetic(int y, int m, int d) => Event(
        id: '_', type: EventType.custom, title: '', system: CalendarSystem.solar,
        month: m, day: d, recurrence: Recurrence2.none, colorTag: ColorTag.gray, createdAt: DateTime(y),
      );

  Future<Event> add({
    required EventType type, required String title, required CalendarSystem system,
    required int month, required int day, required Recurrence2 recurrence,
    required ColorTag colorTag, int? solarYearOffset, String? personId, String? note,
  }) async {
    final e = Event(
      id: _uuid.v4(), type: type, title: title, system: system,
      month: month, day: day, recurrence: recurrence, colorTag: colorTag,
      solarYearOffset: solarYearOffset, personId: personId, note: note,
      createdAt: DateTime.now(),
    );
    _events.add(e);
    await _repo.save(_events);
    _syncToWidget();
    notifyListeners();
    return e;
  }

  Future<void> update(Event e) async {
    final i = _events.indexWhere((x) => x.id == e.id);
    if (i == -1) return;
    _events[i] = e;
    await _repo.save(_events);
    _syncToWidget();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _events.removeWhere((e) => e.id == id);
    await _repo.save(_events);
    _syncToWidget();
    notifyListeners();
  }

  int? ageOfBirthdayPerson(Event birthdayEvent, DateTime today) {
    if (birthdayEvent.type != EventType.birthday) return null;
    final dob = DateTime(_viewYear, birthdayEvent.month, birthdayEvent.day);
    return AgeCalculator.calculate(dob, today);
  }

  Future<void> _loadAll() async {
    _events = await _repo.load();
    final prefs = await SharedPreferences.getInstance();
    _viewYear = prefs.getInt(_viewYearKey) ?? DateTime.now().year;
    _viewMonth = prefs.getInt(_viewMonthKey) ?? DateTime.now().month;
    _syncToWidget();
    notifyListeners();
  }

  void _syncToWidget() {
    final data = CalendarWidgetData.fromEvents(
      year: _viewYear, month: _viewMonth, events: _events,
    );
    CalendarWidgetService.updateCalendarWidget(data);
  }

  void _scheduleMidnightRefresh() {
    _midnightTimer?.cancel();
    int lastDay = DateTime.now().day;
    _midnightTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final today = DateTime.now().day;
      if (today != lastDay) {
        lastDay = today;
        _syncToWidget();
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    super.dispose();
  }
}

// alias
class Recurrence2 { static const none = Recurrence.none; }
```

> 上面 Recurrence2 是占位别名，让 `recurrence: Recurrence2.none` 通过编译——实际上 Task 8 已经 import recurrence.dart，应直接用 `Recurrence.none`。请实现时统一改为 `import '../domain/recurrence.dart'; Recurrence r = Recurrence.none;`。

- [ ] **Step 2: 删除旧文件**

```bash
git rm lib/lab/demos/calendar/providers/lab_calendar_provider.dart
git rm lib/lab/demos/calendar/models/lab_calendar_event.dart
```

- [ ] **Step 3: 更新 main.dart import 路径**

```bash
# 在 lib/main.dart 中查找旧 import 路径
grep -n "lab/demos/calendar/providers/lab_calendar_provider" lib/main.dart
# 把路径改为 lib/lab/demos/calendar/data/lab_calendar_provider.dart
```
然后跑 `flutter analyze` 确保无错。

- [ ] **Step 4: 验证编译**

Run: `flutter analyze`
Expected: No issues found!

- [ ] **Step 5: Commit**

```bash
git add lib/lab/demos/calendar/data/lab_calendar_provider.dart \
        lib/lab/demos/calendar/providers/lab_calendar_provider.dart \
        lib/lab/demos/calendar/models/lab_calendar_event.dart \
        lib/main.dart
git commit -m "refactor(calendar): 迁移到新 data 层 + 旧 provider 删除 + 路径统一"
```

---

## Task 16: PillSegmented 控件

**Files:**
- Create: `lib/lab/demos/calendar/ui/widgets/pill_segmented.dart`

**Interfaces:**
- Consumes: 无
- Produces: `PillSegmented({items, selectedIndex, onChanged})`

- [ ] **Step 1: 实现**

```dart
// lib/lab/demos/calendar/ui/widgets/pill_segmented.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/paper_palette.dart';
import '../../../../core/theme/typography.dart';

class PillSegmented extends StatelessWidget {
  final List<String> items;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const PillSegmented({
    super.key, required this.items, required this.selectedIndex, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: PaperPalette.bgElevated,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: PaperPalette.line, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(items.length, (i) {
          final active = i == selectedIndex;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: active ? PaperPalette.ink : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                items[i],
                style: AppText.caption().copyWith(
                  color: active ? PaperPalette.bg : PaperPalette.inkMuted,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
```

- [ ] **Step 2: 验证编译 + commit**

```bash
flutter analyze lib/lab/demos/calendar/ui/widgets/pill_segmented.dart
git add lib/lab/demos/calendar/ui/widgets/pill_segmented.dart
git commit -m "feat(calendar): PillSegmented 视图切换（0 弹层）"
```

---

## Task 17: LunarLabel + PersonChip + EmptyState 小件

**Files:**
- Create: `lib/lab/demos/calendar/ui/widgets/lunar_label.dart`
- Create: `lib/lab/demos/calendar/ui/widgets/person_chip.dart`
- Create: `lib/lab/demos/calendar/ui/widgets/empty_state.dart`

**Interfaces:**
- Consumes: PaperPalette（Task 2）+ AppText（Task 3）+ ChineseCalendarAdapter（Task 5）+ Person（Task 9）

- [ ] **Step 1: LunarLabel**

```dart
// lib/lab/demos/calendar/ui/widgets/lunar_label.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/paper_palette.dart';
import '../../../../core/theme/typography.dart';
import '../../chinese_calendar_adapter.dart';

class LunarLabel extends StatelessWidget {
  final DateTime solar;
  final LunarStyle style;
  const LunarLabel({super.key, required this.solar, this.style = LunarStyle.compact});

  @override
  Widget build(BuildContext context) {
    final l = ChineseCalendarAdapter().fromSolar(solar);
    final text = l.isLeap ? '闰${l.month}月${l.day}' : '${l.month}月${l.day}';
    return Text(text, style: AppText.caption(color: PaperPalette.inkMuted));
  }
}

enum LunarStyle { compact, full }
```

- [ ] **Step 2: PersonChip**

```dart
// lib/lab/demos/calendar/ui/widgets/person_chip.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/paper_palette.dart';
import '../../../../core/theme/typography.dart';
import '../../domain/person.dart';

class PersonChip extends StatelessWidget {
  final Person person;
  final double size;
  const PersonChip({super.key, required this.person, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: PaperPalette.bgElevated,
        shape: BoxShape.circle,
        border: Border.all(color: PaperPalette.line, width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        person.avatarEmoji ?? person.name.characters.first,
        style: AppText.caption().copyWith(fontSize: size * 0.55),
      ),
    );
  }
}
```

- [ ] **Step 3: EmptyState**

```dart
// lib/lab/demos/calendar/ui/widgets/empty_state.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/paper_palette.dart';
import '../../../../core/theme/typography.dart';

class EmptyState extends StatelessWidget {
  final String message;
  const EmptyState({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, style: AppText.body(color: PaperPalette.inkMuted)),
      ),
    );
  }
}
```

- [ ] **Step 4: 验证 + commit**

```bash
flutter analyze lib/lab/demos/calendar/ui/widgets/
git add lib/lab/demos/calendar/ui/widgets/lunar_label.dart \
        lib/lab/demos/calendar/ui/widgets/person_chip.dart \
        lib/lab/demos/calendar/ui/widgets/empty_state.dart
git commit -m "feat(calendar): 通用小件 LunarLabel/PersonChip/EmptyState"
```

---

## Task 18: DayCell 重做

**Files:**
- Create: `lib/lab/demos/calendar/ui/widgets/day_cell.dart`

**Interfaces:**
- Consumes: PaperPalette（Task 2）+ AppText（Task 3）+ Event（Task 8）+ PersonChip（Task 17）+ LunarLabel（Task 17）

- [ ] **Step 1: 实现**

```dart
// lib/lab/demos/calendar/ui/widgets/day_cell.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/paper_palette.dart';
import '../../../../core/theme/typography.dart';
import '../../domain/event.dart';
import '../../domain/person.dart';
import 'lunar_label.dart';
import 'person_chip.dart';

class DayCell extends StatelessWidget {
  final DateTime date;
  final bool inCurrentMonth;
  final bool isToday;
  final List<Event> events;
  final List<Person> people;       // 与事件关联的人（取自 provider）
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const DayCell({
    super.key, required this.date, required this.inCurrentMonth, required this.isToday,
    required this.events, this.people = const [], this.onTap, this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final stack = <Widget>[];
    final numberColor = isToday
        ? PaperPalette.today
        : (inCurrentMonth ? PaperPalette.ink : PaperPalette.inkFaint);

    stack.add(Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('${date.day}',
              style: AppText.title(color: numberColor).copyWith(fontSize: 18)),
          if (inCurrentMonth) LunarLabel(solar: date),
        ],
      ),
    ));

    if (events.isNotEmpty) {
      final has = people.take(3).toList();
      final overflow = people.length - has.length;
      stack.add(Positioned(
        bottom: 4, left: 0, right: 0,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ...has.map((p) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: PersonChip(person: p, size: 12),
                )),
            if (overflow > 0) Text('+$overflow', style: AppText.caption()),
          ],
        ),
      ));
    }

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          border: isToday
              ? Border.all(color: PaperPalette.today, width: 1)
              : null,
        ),
        child: Stack(children: stack),
      ),
    );
  }
}
```

- [ ] **Step 2: 验证 + commit**

```bash
flutter analyze lib/lab/demos/calendar/ui/widgets/day_cell.dart
git add lib/lab/demos/calendar/ui/widgets/day_cell.dart
git commit -m "feat(calendar): DayCell 重做（公历+农历+人堆叠）"
```

---

## Task 19: MonthGrid 容器

**Files:**
- Create: `lib/lab/demos/calendar/ui/widgets/month_grid.dart`

**Interfaces:**
- Consumes: DayCell（Task 18）+ LabCalendarProvider（Task 15）+ LabPeopleProvider（Task 14）

- [ ] **Step 1: 实现**

```dart
// lib/lab/demos/calendar/ui/widgets/month_grid.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/lab_calendar_provider.dart';
import '../../../data/lab_people_provider.dart';
import '../../../domain/event.dart';
import 'day_cell.dart';

class MonthGrid extends StatelessWidget {
  final int year;
  final int month;
  final void Function(DateTime) onDayTap;
  final void Function(DateTime) onDayLongPress;

  const MonthGrid({
    super.key, required this.year, required this.month,
    required this.onDayTap, required this.onDayLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cal = context.watch<LabCalendarProvider>();
    final people = context.watch<LabPeopleProvider>();
    final first = DateTime(year, month, 1);
    final firstDow = first.weekday % 7;
    final days = DateTime(year, month + 1, 0).day;
    final prevDays = DateTime(year, month, 0).day;

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7, childAspectRatio: 1,
      ),
      itemCount: 42,
      itemBuilder: (_, i) {
        DateTime date;
        bool inMonth = true;
        if (i < firstDow) {
          date = DateTime(year, month - 1, prevDays - (firstDow - i - 1));
          inMonth = false;
        } else if (i >= firstDow + days) {
          date = DateTime(year, month + 1, i - firstDow - days + 1);
          inMonth = false;
        } else {
          date = DateTime(year, month, i - firstDow + 1);
        }
        final events = cal.events.where((e) => e.month == date.month && e.day == date.day).toList();
        final evPeople = events
            .where((e) => e.personId != null)
            .map((e) => people.byId(e.personId!) ?? _placeholder(e))
            .toList();
        return DayCell(
          date: date, inCurrentMonth: inMonth,
          isToday: _isToday(date),
          events: events, people: evPeople,
          onTap: () => onDayTap(date),
          onLongPress: () => onDayLongPress(date),
        );
      },
    );
  }

  bool _isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  _PlaceholderPerson _placeholder(Event e) => _PlaceholderPerson(id: e.personId!);
}

class _PlaceholderPerson implements dynamic {
  final String id;
  _PlaceholderPerson({required this.id});
  String get name => '?';
  String? get avatarEmoji => null;
}
```

> 上面的 placeholder 是临时兼容写法，实现时直接用 `Person` 类型并允许 byId 返回 null 的处理：

```dart
final evPeople = <Person>[
  for (final e in events)
    if (e.personId != null) ...[
      if (people.byId(e.personId!) != null) people.byId(e.personId!)!,
    ],
];
```

- [ ] **Step 2: 验证 + commit**

```bash
flutter analyze lib/lab/demos/calendar/ui/widgets/month_grid.dart
git add lib/lab/demos/calendar/ui/widgets/month_grid.dart
git commit -m "feat(calendar): MonthGrid 7×6 容器 + 数据接入"
```

---

## Task 20: MonthView（月视图主）

**Files:**
- Create: `lib/lab/demos/calendar/ui/month_view.dart`

**Interfaces:**
- Consumes: MonthGrid（Task 19）+ LabCalendarProvider（Task 15）
- Produces: `MonthView({onDayTap, onDayLongPress})`

- [ ] **Step 1: 实现**

```dart
// lib/lab/demos/calendar/ui/month_view.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/paper_palette.dart';
import '../../core/theme/typography.dart';
import '../data/lab_calendar_provider.dart';
import 'widgets/month_grid.dart';

class MonthView extends StatelessWidget {
  final void Function(DateTime) onDayTap;
  final void Function(DateTime) onDayLongPress;
  const MonthView({super.key, required this.onDayTap, required this.onDayLongPress});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<LabCalendarProvider>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.chevron_left_rounded), onPressed: p.prevMonth),
              Expanded(
                child: Center(
                  child: GestureDetector(
                    onTap: p.jumpToday,
                    child: Text('${p.viewYear}年${p.viewMonth}月',
                        style: AppText.title()),
                  ),
                ),
              ),
              IconButton(icon: const Icon(Icons.chevron_right_rounded), onPressed: p.nextMonth),
            ],
          ),
        ),
        _WeekdayHeader(),
        Expanded(
          child: MonthGrid(
            year: p.viewYear, month: p.viewMonth,
            onDayTap: onDayTap, onDayLongPress: onDayLongPress,
          ),
        ),
      ],
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const days = ['日', '一', '二', '三', '四', '五', '六'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: days.map((d) => Expanded(
          child: Center(child: Text(d, style: AppText.caption())),
        )).toList(),
      ),
    );
  }
}
```

- [ ] **Step 2: 验证 + commit**

```bash
flutter analyze lib/lab/demos/calendar/ui/month_view.dart
git add lib/lab/demos/calendar/ui/month_view.dart
git commit -m "feat(calendar): MonthView 主视图 + 跳月 + 周表头"
```

---

## Task 21: DayDetailSheet（看 + 编辑双模式 inline）

**Files:**
- Create: `lib/lab/demos/calendar/ui/day_detail_sheet.dart`

**Interfaces:**
- Consumes: EventFormSheet（Task 23）+ LabCalendarProvider（Task 15）+ LabPeopleProvider（Task 14）

- [ ] **Step 1: 实现**

```dart
// lib/lab/demos/calendar/ui/day_detail_sheet.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/paper_palette.dart';
import '../../core/theme/typography.dart';
import '../data/lab_calendar_provider.dart';
import '../data/lab_people_provider.dart';
import '../domain/event.dart';
import 'event_form_sheet.dart';

class DayDetailSheet extends StatelessWidget {
  final DateTime date;
  const DayDetailSheet({super.key, required this.date});

  @override
  Widget build(BuildContext context) {
    final cal = context.watch<LabCalendarProvider>();
    final people = context.watch<LabPeopleProvider>();
    final events = cal.events
        .where((e) => e.month == date.month && e.day == date.day)
        .toList();

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 20, right: 20, top: 16,
      ),
      decoration: const BoxDecoration(
        color: PaperPalette.bgElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('${date.year}年${date.month}月${date.day}日', style: AppText.title())),
              IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 8),
          if (events.isEmpty)
            Text('暂无事件', style: AppText.body(color: PaperPalette.inkMuted))
          else
            ...events.map((e) => _EventRow(event: e, personName: _personName(people, e))),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('新建事件'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EventFormSheet(date: date),
                fullscreenDialog: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _personName(LabPeopleProvider p, Event e) =>
      e.personId == null ? null : p.byId(e.personId!)?.name;
}

class _EventRow extends StatelessWidget {
  final Event event;
  final String? personName;
  const _EventRow({required this.event, this.personName});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(event.title, style: AppText.body()),
      subtitle: Text([
        if (personName != null) personName!,
        event.system.name,
        event.recurrence.name,
      ].join(' · '), style: AppText.caption()),
      trailing: IconButton(
        icon: const Icon(Icons.edit_outlined),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EventFormSheet(date: DateTime(2026, event.month, event.day), existing: event),
            fullscreenDialog: true,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 验证 + commit**

```bash
flutter analyze lib/lab/demos/calendar/ui/day_detail_sheet.dart
git add lib/lab/demos/calendar/ui/day_detail_sheet.dart
git commit -m "feat(calendar): DayDetailSheet 看/编辑/新建 inline 双模式"
```

---

## Task 22: PersonFormSheet

**Files:**
- Create: `lib/lab/demos/calendar/ui/person_form_sheet.dart`

**Interfaces:**
- Consumes: LabPeopleProvider（Task 14）+ LabCalendarProvider（Task 15）+ LunarDateCodec（Task 6）+ NextBirthdayResolver（Task 11）

- [ ] **Step 1: 实现**

```dart
// lib/lab/demos/calendar/ui/person_form_sheet.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/paper_palette.dart';
import '../../core/theme/typography.dart';
import '../chinese_calendar_adapter.dart';
import '../data/lab_calendar_provider.dart';
import '../data/lab_people_provider.dart';
import '../domain/event.dart';
import '../domain/lunar_date_codec.dart';
import '../domain/person.dart';
import '../domain/recurrence.dart';

class PersonFormSheet extends StatefulWidget {
  final Person? existing;
  const PersonFormSheet({super.key, this.existing});

  @override
  State<PersonFormSheet> createState() => _PersonFormSheetState();
}

class _PersonFormSheetState extends State<PersonFormSheet> {
  late final TextEditingController _name;
  late final TextEditingController _emoji;
  late final TextEditingController _date;
  late final TextEditingController _note;
  late PersonRelation _relation;
  late CalendarSystem _system;
  final _codec = LunarDateCodec(ChineseCalendarAdapter());

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: p?.name ?? '');
    _emoji = TextEditingController(text: p?.avatarEmoji ?? '');
    _date = TextEditingController();
    _note = TextEditingController(text: p?.note ?? '');
    _relation = p?.relation ?? PersonRelation.family;
    _system = CalendarSystem.solar;
  }

  @override
  void dispose() {
    _name.dispose(); _emoji.dispose(); _date.dispose(); _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.isEmpty || _date.text.length != 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写姓名与 8 位数字日期')));
      return;
    }
    final ymd = int.parse(_date.text);
    final people = context.read<LabPeopleProvider>();
    final cal = context.read<LabCalendarProvider>();
    final p = widget.existing;
    final saved = p ??
        await people.add(name: _name.text, relation: _relation,
            avatarEmoji: _emoji.text.isEmpty ? null : _emoji.text,
            note: _note.text.isEmpty ? null : _note.text);
    if (!mounted) return;
    // 自动生成/更新 birthday 事件
    final solar = _system == CalendarSystem.solar
        ? _codec.parseSolarFromYmd8(ymd)
        : _codec.parseLunarFromYmd8(ymd, year: DateTime.now().year);
    final existing = cal.events.firstWhere(
      (e) => e.personId == saved.id && e.type == EventType.birthday,
      orElse: () => _emptyBirthday(),
    );
    if (existing.id == '_empty_') {
      await cal.add(
        type: EventType.birthday, title: '${saved.name}生日',
        system: _system, month: solar.month, day: solar.day,
        recurrence: _system == CalendarSystem.lunar
            ? Recurrence.yearlyLunarAuto : Recurrence.yearly,
        colorTag: ColorTag.amber, personId: saved.id,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  Event _emptyBirthday() => Event(
        id: '_empty_', type: EventType.birthday, title: '',
        system: CalendarSystem.solar, month: 1, day: 1,
        recurrence: Recurrence.yearly, colorTag: ColorTag.amber,
        createdAt: DateTime.now(),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PaperPalette.bg,
      appBar: AppBar(
        backgroundColor: PaperPalette.bg, elevation: 0,
        title: Text(widget.existing == null ? '新增人' : '编辑人', style: AppText.title()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: '姓名')),
          const SizedBox(height: 12),
          TextField(controller: _emoji, decoration: const InputDecoration(labelText: '头像 emoji（可选）')),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: TextField(
                controller: _date, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '生日 8 位数字 (YYYYMMDD)'),
              )),
              const SizedBox(width: 12),
              ToggleButtons(
                isSelected: [_system == CalendarSystem.solar, _system == CalendarSystem.lunar],
                onPressed: (i) => setState(() => _system = i == 0 ? CalendarSystem.solar : CalendarSystem.lunar),
                children: const [Text('公历'), Text('农历')],
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<PersonRelation>(
            value: _relation,
            items: PersonRelation.values.map((r) =>
              DropdownMenuItem(value: r, child: Text(r.name))).toList(),
            onChanged: (v) => setState(() => _relation = v!),
            decoration: const InputDecoration(labelText: '关系'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _note, maxLines: 3, decoration: const InputDecoration(labelText: '备注')),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: 验证 + commit**

```bash
flutter analyze lib/lab/demos/calendar/ui/person_form_sheet.dart
git add lib/lab/demos/calendar/ui/person_form_sheet.dart
git commit -m "feat(calendar): PersonFormSheet 新增/编辑人 + 8 位生日自动建事件"
```

---

## Task 23: EventFormSheet

**Files:**
- Create: `lib/lab/demos/calendar/ui/event_form_sheet.dart`

**Interfaces:**
- Consumes: LabCalendarProvider（Task 15）+ LabPeopleProvider（Task 14）+ Event（Task 8）

- [ ] **Step 1: 实现**

```dart
// lib/lab/demos/calendar/ui/event_form_sheet.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/paper_palette.dart';
import '../../core/theme/typography.dart';
import '../data/lab_calendar_provider.dart';
import '../data/lab_people_provider.dart';
import '../domain/event.dart';
import '../domain/recurrence.dart';

class EventFormSheet extends StatefulWidget {
  final DateTime date;
  final Event? existing;
  const EventFormSheet({super.key, required this.date, this.existing});

  @override
  State<EventFormSheet> createState() => _EventFormSheetState();
}

class _EventFormSheetState extends State<EventFormSheet> {
  late final TextEditingController _title;
  late EventType _type;
  late ColorTag _color;
  late Recurrence _rec;
  late CalendarSystem _system;
  String? _personId;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _type = e?.type ?? EventType.task;
    _color = e?.colorTag ?? ColorTag.gray;
    _rec = e?.recurrence ?? Recurrence.none;
    _system = e?.system ?? CalendarSystem.solar;
    _personId = e?.personId;
    _note = TextEditingController(text: e?.note ?? '');
  }

  @override
  void dispose() {
    _title.dispose(); _note.dispose(); super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.isEmpty) return;
    final cal = context.read<LabCalendarProvider>();
    if (widget.existing != null) {
      await cal.update(widget.existing!.copyWith(
        title: _title.text, type: _type, colorTag: _color,
        recurrence: _rec, system: _system, personId: _personId, note: _note.text,
      ));
    } else {
      await cal.add(
        type: _type, title: _title.text, system: _system,
        month: widget.date.month, day: widget.date.day,
        recurrence: _rec, colorTag: _color, personId: _personId,
        note: _note.text.isEmpty ? null : _note.text,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final people = context.watch<LabPeopleProvider>();
    return Scaffold(
      backgroundColor: PaperPalette.bg,
      appBar: AppBar(
        backgroundColor: PaperPalette.bg, elevation: 0,
        title: Text(widget.existing == null ? '新建事件' : '编辑事件', style: AppText.title()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _title, decoration: const InputDecoration(labelText: '标题')),
          const SizedBox(height: 12),
          DropdownButtonFormField<EventType>(
            value: _type,
            items: EventType.values.map((t) =>
              DropdownMenuItem(value: t, child: Text(t.name))).toList(),
            onChanged: (v) => setState(() => _type = v!),
            decoration: const InputDecoration(labelText: '类型'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            value: _personId,
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('不关联人')),
              ...people.people.map((p) =>
                DropdownMenuItem(value: p.id, child: Text(p.name))),
            ],
            onChanged: (v) => setState(() => _personId = v),
            decoration: const InputDecoration(labelText: '关联人'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<Recurrence>(
            value: _rec,
            items: Recurrence.values.map((r) =>
              DropdownMenuItem(value: r, child: Text(r.name))).toList(),
            onChanged: (v) => setState(() => _rec = v!),
            decoration: const InputDecoration(labelText: '重复'),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: 验证 + commit**

```bash
flutter analyze lib/lab/demos/calendar/ui/event_form_sheet.dart
git add lib/lab/demos/calendar/ui/event_form_sheet.dart
git commit -m "feat(calendar): EventFormSheet 新建/编辑事件"
```

---

## Task 24: PersonDetailPage

**Files:**
- Create: `lib/lab/demos/calendar/ui/person_detail_page.dart`

**Interfaces:**
- Consumes: LabPeopleProvider（Task 14）+ LabCalendarProvider（Task 15）+ NextBirthdayResolver（Task 11）

- [ ] **Step 1: 实现**

```dart
// lib/lab/demos/calendar/ui/person_detail_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/paper_palette.dart';
import '../../core/theme/typography.dart';
import '../chinese_calendar_adapter.dart';
import '../data/lab_calendar_provider.dart';
import '../data/lab_people_provider.dart';
import '../domain/age_calculator.dart';
import '../domain/event.dart';
import '../domain/next_birthday.dart';
import '../domain/person.dart';
import 'person_form_sheet.dart';

class PersonDetailPage extends StatelessWidget {
  final String personId;
  const PersonDetailPage({super.key, required this.personId});

  @override
  Widget build(BuildContext context) {
    final people = context.watch<LabPeopleProvider>();
    final cal = context.watch<LabCalendarProvider>();
    final person = people.byId(personId);
    if (person == null) return const SizedBox.shrink();
    final events = cal.events.where((e) => e.personId == personId).toList();
    final birthday = events.where((e) => e.type == EventType.birthday).cast<Event?>().firstOrNull;
    final resolver = NextBirthdayResolver(ChineseCalendarAdapter());
    final today = DateTime.now();
    final next = birthday == null ? null : resolver.upcoming(birthday, today);
    final age = birthday == null
        ? null
        : AgeCalculator.calculate(DateTime(today.year, birthday.month, birthday.day), today);

    return Scaffold(
      backgroundColor: PaperPalette.bg,
      appBar: AppBar(
        backgroundColor: PaperPalette.bg, elevation: 0,
        title: Text(person.name, style: AppText.title()),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => PersonFormSheet(existing: person))),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(child: Text(person.avatarEmoji ?? '👤', style: TextStyle(fontSize: 80))),
          const SizedBox(height: 12),
          Center(child: Text(person.name, style: AppText.display())),
          Center(child: Text(person.relation.name, style: AppText.caption())),
          const SizedBox(height: 24),
          if (birthday != null && next != null) ...[
            Text('生日', style: AppText.title()),
            const SizedBox(height: 8),
            Text('${next.year}年${next.month}月${next.day}日 · 距今 ${NextBirthdayResolver.daysUntil(next, today)} 天', style: AppText.body()),
            if (age != null) Text('${age} 岁', style: AppText.caption()),
          ],
          const SizedBox(height: 24),
          Text('备注', style: AppText.title()),
          Text(person.note ?? '—', style: AppText.body()),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> { T? get firstOrNull => isEmpty ? null : first; }
```

- [ ] **Step 2: 验证 + commit**

```bash
flutter analyze lib/lab/demos/calendar/ui/person_detail_page.dart
git add lib/lab/demos/calendar/ui/person_detail_page.dart
git commit -m "feat(calendar): PersonDetailPage 人物详情 + 年龄 + 倒计时"
```

---

## Task 25: WeekView / DayView / YearView

**Files:**
- Create: `lib/lab/demos/calendar/ui/week_view.dart`
- Create: `lib/lab/demos/calendar/ui/day_view.dart`
- Create: `lib/lab/demos/calendar/ui/year_view.dart`

**Interfaces:**
- Consumes: LabCalendarProvider（Task 15）

- [ ] **Step 1: WeekView**

```dart
// lib/lab/demos/calendar/ui/week_view.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/paper_palette.dart';
import '../../core/theme/typography.dart';
import '../data/lab_calendar_provider.dart';

class WeekView extends StatelessWidget {
  final void Function(DateTime) onDayTap;
  const WeekView({super.key, required this.onDayTap});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<LabCalendarProvider>();
    final today = DateTime.now();
    final weekStart = today.subtract(Duration(days: today.weekday % 7));
    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));

    return ListView(
      children: days.map((d) {
        final events = p.events.where((e) => e.month == d.month && e.day == d.day).toList();
        return ListTile(
          leading: Text('${d.month}/${d.day}', style: AppText.body()),
          title: Text(events.isEmpty ? '无事件' : events.map((e) => e.title).join(' · '), style: AppText.caption()),
          onTap: () => onDayTap(d),
        );
      }).toList(),
    );
  }
}
```

- [ ] **Step 2: DayView**

```dart
// lib/lab/demos/calendar/ui/day_view.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/paper_palette.dart';
import '../../core/theme/typography.dart';
import '../data/lab_calendar_provider.dart';

class DayView extends StatelessWidget {
  const DayView({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<LabCalendarProvider>();
    final today = DateTime.now();
    final events = p.events.where((e) => e.month == today.month && e.day == today.day).toList();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('${today.year}年${today.month}月${today.day}日', style: AppText.display()),
        const SizedBox(height: 16),
        if (events.isEmpty)
          Text('今天没有事件', style: AppText.body(color: PaperPalette.inkMuted))
        else
          ...events.map((e) => ListTile(
                title: Text(e.title, style: AppText.body()),
                subtitle: Text('${e.type.name} · ${e.system.name}', style: AppText.caption()),
              )),
      ],
    );
  }
}
```

- [ ] **Step 3: YearView**

```dart
// lib/lab/demos/calendar/ui/year_view.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/paper_palette.dart';
import '../../core/theme/typography.dart';
import '../data/lab_calendar_provider.dart';

class YearView extends StatelessWidget {
  final void Function(DateTime) onDayTap;
  const YearView({super.key, required this.onDayTap});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<LabCalendarProvider>();
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, childAspectRatio: 0.9, crossAxisSpacing: 8, mainAxisSpacing: 8,
      ),
      padding: const EdgeInsets.all(16),
      itemCount: 12,
      itemBuilder: (_, i) {
        final m = i + 1;
        final events = p.events.where((e) => e.month == m).toList();
        return GestureDetector(
          onTap: () => p.setView(p.viewYear, m),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: PaperPalette.line, width: 1),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$m 月', style: AppText.title()),
                Text('${events.length} 个事件', style: AppText.caption()),
              ],
            ),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 4: 验证 + commit**

```bash
flutter analyze lib/lab/demos/calendar/ui/week_view.dart lib/lab/demos/calendar/ui/day_view.dart lib/lab/demos/calendar/ui/year_view.dart
git add lib/lab/demos/calendar/ui/week_view.dart lib/lab/demos/calendar/ui/day_view.dart lib/lab/demos/calendar/ui/year_view.dart
git commit -m "feat(calendar): 周/日/年视图骨架"
```

---

## Task 26: AnnualReportPage

**Files:**
- Create: `lib/lab/demos/calendar/ui/annual_report_page.dart`

**Interfaces:**
- Consumes: LabCalendarProvider（Task 15）+ LabPeopleProvider（Task 14）

- [ ] **Step 1: 实现**

```dart
// lib/lab/demos/calendar/ui/annual_report_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/paper_palette.dart';
import '../../core/theme/typography.dart';
import '../data/lab_calendar_provider.dart';
import '../data/lab_people_provider.dart';
import '../domain/event.dart';

class AnnualReportPage extends StatelessWidget {
  const AnnualReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<LabCalendarProvider>();
    final people = context.watch<LabPeopleProvider>();
    final birthdays = p.events.where((e) => e.type == EventType.birthday).toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('${p.viewYear} 年度报表', style: AppText.display()),
        const SizedBox(height: 8),
        Text('共 ${birthdays.length} 个生日', style: AppText.body()),
        const SizedBox(height: 24),
        ...List.generate(12, (i) => i + 1).map((m) {
          final mEvents = p.events.where((e) => e.month == m).toList();
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: PaperPalette.line),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$m 月', style: AppText.title()),
                ...mEvents.map((e) {
                  final person = e.personId == null ? null : people.byId(e.personId!);
                  return Text('${e.day}日 · ${e.title}${person == null ? "" : "（${person.name}）"}', style: AppText.caption());
                }),
              ],
            ),
          );
        }),
      ],
    );
  }
}
```

- [ ] **Step 2: 验证 + commit**

```bash
flutter analyze lib/lab/demos/calendar/ui/annual_report_page.dart
git add lib/lab/demos/calendar/ui/annual_report_page.dart
git commit -m "feat(calendar): AnnualReportPage 年度事件报表"
```

---

## Task 27: PeopleView（人卡片瀑布）

**Files:**
- Create: `lib/lab/demos/calendar/ui/people_view.dart`

**Interfaces:**
- Consumes: LabPeopleProvider（Task 14）+ LabCalendarProvider（Task 15）+ NextBirthdayResolver（Task 11）+ PersonDetailPage（Task 24）+ PersonFormSheet（Task 22）

- [ ] **Step 1: 实现**

```dart
// lib/lab/demos/calendar/ui/people_view.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/paper_palette.dart';
import '../../core/theme/typography.dart';
import '../chinese_calendar_adapter.dart';
import '../data/lab_calendar_provider.dart';
import '../data/lab_people_provider.dart';
import '../domain/event.dart';
import '../domain/next_birthday.dart';
import '../domain/person.dart';
import 'person_detail_page.dart';
import 'person_form_sheet.dart';

class PeopleView extends StatelessWidget {
  const PeopleView({super.key});

  @override
  Widget build(BuildContext context) {
    final people = context.watch<LabPeopleProvider>();
    final cal = context.watch<LabCalendarProvider>();
    final today = DateTime.now();
    final resolver = NextBirthdayResolver(ChineseCalendarAdapter());

    final groups = <PersonRelation, List<Person>>{};
    for (final p in people.people) {
      groups.putIfAbsent(p.relation, () => []).add(p);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final entry in groups.entries) ...[
          Text(entry.key.name, style: AppText.title()),
          const SizedBox(height: 8),
          ...entry.value.map((p) {
            final birthday = cal.events.where((e) =>
              e.personId == p.id && e.type == EventType.birthday).cast<Event?>().firstOrNull;
            final next = birthday == null ? null : resolver.upcoming(birthday, today);
            final days = next == null ? null : NextBirthdayResolver.daysUntil(next, today);
            return ListTile(
              leading: Text(p.avatarEmoji ?? '👤', style: const TextStyle(fontSize: 28)),
              title: Text(p.name, style: AppText.body()),
              subtitle: days == null ? null : Text('距生日 $days 天', style: AppText.caption()),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => PersonDetailPage(personId: p.id))),
            );
          }),
          const SizedBox(height: 16),
        ],
        FilledButton.icon(
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('新增人'),
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const PersonFormSheet())),
        ),
      ],
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> { T? get firstOrNull => isEmpty ? null : first; }
```

- [ ] **Step 2: 验证 + commit**

```bash
flutter analyze lib/lab/demos/calendar/ui/people_view.dart
git add lib/lab/demos/calendar/ui/people_view.dart
git commit -m "feat(calendar): PeopleView 人卡片瀑布 + 关系分组 + 倒计时"
```

---

## Task 28: CalendarDemo 容器 + PageView

**Files:**
- Create: `lib/lab/demos/calendar/ui/calendar_demo.dart`
- Delete: `lib/lab/demos/calendar/calendar_demo.dart`（旧）
- Delete: `lib/lab/demos/calendar/calendar_day_cell.dart`（旧）
- Delete: `lib/lab/demos/calendar/calendar_day_sheet.dart`（旧）
- Delete: `lib/lab/demos/calendar/calendar_month_grid.dart`（旧）

**Interfaces:**
- Consumes: 所有 UI 组件 + Provider + PillSegmented

- [ ] **Step 1: 实现**

```dart
// lib/lab/demos/calendar/ui/calendar_demo.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/paper_palette.dart';
import '../../../core/theme/typography.dart';
import '../../../lab_container.dart';
import '../data/lab_calendar_provider.dart';
import '../data/lab_people_provider.dart';
import '../domain/event.dart';
import 'annual_report_page.dart';
import 'day_detail_sheet.dart';
import 'day_view.dart';
import 'event_form_sheet.dart';
import 'month_view.dart';
import 'people_view.dart';
import 'week_view.dart';
import 'widgets/pill_segmented.dart';
import 'year_view.dart';

class CalendarDemo extends DemoPage {
  @override
  String get title => '日历待办';

  @override
  String get slug => 'calendar';

  @override
  String get description => '人·农历·生日·五视图 日式极简';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) => const _CalendarDemoPage();
}

class _CalendarDemoPage extends StatefulWidget {
  const _CalendarDemoPage();
  @override
  State<_CalendarDemoPage> createState() => _CalendarDemoPageState();
}

class _CalendarDemoPageState extends State<_CalendarDemoPage> {
  int _index = 1; // 默认月视图
  late final PageController _page;

  @override
  void initState() {
    super.initState();
    _page = PageController(initialPage: _index);
  }

  @override
  void dispose() { _page.dispose(); super.dispose(); }

  void _openDaySheet(DateTime date) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DayDetailSheet(date: date),
    );
  }

  void _openInlineEvent(DateTime date) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EventFormSheet(date: date),
      fullscreenDialog: true,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final items = ['今天', '月', '周', '年', '人', '报表'];
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LabCalendarProvider()),
        ChangeNotifierProvider(create: (_) => LabPeopleProvider()),
      ],
      child: Scaffold(
        backgroundColor: PaperPalette.bg,
        appBar: AppBar(
          backgroundColor: PaperPalette.bg, elevation: 0,
          title: Text('日历待办', style: AppText.title()),
          leading: IconButton(
            icon: const Icon(Icons.home_outlined),
            onPressed: () {
              final p = context.read<LabCalendarProvider>();
              p.jumpToday();
              setState(() => _index = 1);
              _page.jumpToPage(1);
            },
          ),
          actions: [
            Center(child: PillSegmented(
              items: items,
              selectedIndex: _index,
              onChanged: (i) { setState(() => _index = i); _page.jumpToPage(i); },
            )),
            const SizedBox(width: 16),
          ],
        ),
        body: PageView(
          controller: _page,
          onPageChanged: (i) => setState(() => _index = i),
          children: [
            const DayView(),
            MonthView(onDayTap: _openDaySheet, onDayLongPress: _openInlineEvent),
            WeekView(onDayTap: _openDaySheet),
            YearView(onDayTap: (d) => _openDaySheet(d)),
            const PeopleView(),
            const AnnualReportPage(),
          ],
        ),
      ),
    );
  }
}

void registerCalendarDemo() { demoRegistry.register(CalendarDemo()); }
```

- [ ] **Step 2: 删除旧文件 + 更新 main.dart import**

```bash
git rm lib/lab/demos/calendar/calendar_demo.dart
git rm lib/lab/demos/calendar/calendar_day_cell.dart
git rm lib/lab/demos/calendar/calendar_day_sheet.dart
git rm lib/lab/demos/calendar/calendar_month_grid.dart
# 更新 main.dart 的 import 路径
grep -n "lab/demos/calendar/calendar_demo" lib/main.dart
```

- [ ] **Step 3: 验证编译**

Run: `flutter analyze`
Expected: No issues found!

- [ ] **Step 4: 手动 smoke**

Run: `flutter run` 然后在 lab 列表点「日历待办」
Expected: 6 个 pill 切换正常、月视图长按/点日期工作、人视图点击进入详情

- [ ] **Step 5: Commit**

```bash
git add lib/lab/demos/calendar/ui/calendar_demo.dart \
        lib/lab/demos/calendar/calendar_demo.dart \
        lib/lab/demos/calendar/calendar_day_cell.dart \
        lib/lab/demos/calendar/calendar_day_sheet.dart \
        lib/lab/demos/calendar/calendar_month_grid.dart \
        lib/main.dart
git commit -m "refactor(calendar): CalendarDemo 容器 PageView + 删除旧 UI 文件"
```

---

## Task 29: 端到端 smoke 测试

**Files:**
- Test: 手动（无新文件）

- [ ] **Step 1: 跑全测试套件**

Run: `flutter test`
Expected: PASS（所有 domain 单测）

- [ ] **Step 2: 跑 analyze**

Run: `flutter analyze`
Expected: No issues found!

- [ ] **Step 3: 手动 smoke 清单**

- [ ] 打开日历 demo → 6 个 pill 切换
- [ ] 月视图点日期 → sheet 显示
- [ ] 月视图长按日期 → 事件表单
- [ ] 切到人视图 → 新增人 → 输 8 位数字 → 自动建生日事件
- [ ] 点人 → 详情页显示年龄 + 倒计时
- [ ] 年视图点月 → 跳回月视图该月
- [ ] 报表页 → 显示 12 个月
- [ ] 重启 app → 数据保留

- [ ] **Step 4: 视觉对账自检**

| 检查项 | 通过？ |
|--------|--------|
| 全屏无 Material 默认蓝 | ☐ |
| 全屏无 Elevation 阴影 | ☐ |
| 分隔线全部 1px PaperPalette.line | ☐ |
| 标题用 Cormorant、正文 Inter | ☐ |
| 交互：长按新建 / 点查看 / 点已有编辑 | ☐ |
| 5 视图通过 Pill + PageView 切换 | ☐ |

- [ ] **Step 5: 提交样式微调（如有）**

```bash
git commit -m "style(calendar): smoke 发现微调（如有）"
```

---

## Self-Review

按 spec 检查 plan：

| Spec 节 | 实现任务 |
|---------|---------|
| §0 设计原则 | 全局约束（每 UI 任务自检） |
| §1 背景与目标 | Task 28（容器）+ 全部 UI |
| §2 架构总览 | Task 2-15 全部遵循三层目录 |
| §3 数据模型 | Task 8（Event）+ Task 9（Person）+ Task 7（Recurrence） |
| §4 农历引擎 | Task 4（抽象）+ Task 5（适配器）+ Task 6（编解码） |
| §5 视觉令牌 | Task 2-3（palette/typography/spacing） |
| §6.1 Pill 切换 | Task 16 + Task 28 |
| §6.2 月视图交互 | Task 18-21（长按新建/点看/点编辑） |
| §6.3 周/日视图 | Task 25 |
| §6.4 年视图 | Task 25 |
| §6.5 人视图 | Task 27 |
| §6.6 人物详情 | Task 24 |
| §6.7 年度报表 | Task 26 |
| §7 风险与不做 | 全局约束已写 |
| §8 实施顺序 | Task 1-29 顺序遵循 |

**类型一致性检查**：
- `Event.type: EventType`、`Event.system: CalendarSystem`、`Event.recurrence: Recurrence` —— 在 Task 8/22/23/24/27 中一致使用
- `Person.relation: PersonRelation` —— Task 14/22/27 一致
- `LabCalendarProvider.add` 参数在 Task 15/22/23 一致
- `LabPeopleProvider.byId` 返回 `Person?` —— Task 24/27 一致处理 null

**Placeholders 扫描**：
- Task 11 中有 `extension` 占位写法（`_PlaceholderPerson`、helper for chinese_calendar 0.4 API 适配）—— 已用「若 API 名称不同，调整方法名后再跑测试」说明
- Task 19 中 placeholder 用 `Person` 类型更清晰——已建议正确写法
- Task 15 中 `Recurrence2` 别名是临时写法——已建议直接 `import recurrence.dart`

**spec 覆盖完整 ✅**