# 2026-07-27 日历待办 demo 进化设计 spec

> 作者：Claude（brainstorming 会话）
> 状态：草稿，待用户审阅

## 0. 设计原则（硬性约束）

每个交互决策都必须通过下面四条过滤，不通过就不做：

| 原则 | 含义 | 反例（禁止） | 正例 |
|------|------|-------------|------|
| **快** | 能不弹层完成的就不弹层 | 加号 → ModalBottomSheet → 表单 | 长按单元格 → inline 速记条直接输入 |
| **少点击** | 默认行为覆盖 80% 场景 | 「添加按钮 + 全表单」是唯一路径 | 长按 = 新建；点 = 看；点已有 = 编辑（同一界面三态） |
| **准** | 一个动作只有一种结果 | 「点空白处 + 点 +」二选一不明确 | 长按 = 新建；点 = 看；不存在歧义 |
| **丰富** | 关键信息全在场，留白给足 | 信息塞满每寸空间 | 单屏展示 农历+公历+人+事件+生肖+倒计时，留白 50% |

## 1. 背景与目标

`lib/lab/demos/calendar/` 当前是一个简单 demo：
- 单一 `LabCalendarEvent` 模型（无"人"概念）
- 单月 7×6 网格 + 圆环 cell 用等分弧做颜色标记
- 底部 sheet 管理事件，无农历/生肖
- 同步桌面 widget（保留）
- UI 是纯白底 + Material 默认蓝，"塑料感"明显

目标：
1. 引入「人」模型，支持生日场景极其细节优化（公历/农历双轨、8 位数字日期输入、生肖、未来 N 年推算）
2. 接入农历引擎，支持农历月日、生肖、农历节日（**不做**干支、宜忌）
3. 视图体系扩展为 月/周/日/年/年度报表 五个，可左右滑动快速切换
4. 视觉系统从纯白塑料感进化为**日式极简**——哑光奶白底、墨黑细字、衬线大标题、克制动效
5. **激进重构交互**：用上面 4 条原则重新过所有交互

## 2. 架构总览

```
lib/
  core/
    theme/                       # 新增：日式极简设计令牌
      paper_palette.dart         # 奶白底、墨黑、淡彩
      typography.dart            # Cormorant + Inter
      spacing.dart               # 4/8/12/16/24
  lab/demos/calendar/
    domain/
      lunar_calendar.dart        # chinese_calendar 封装（接口隔离，便于替换）
      lunar_date_codec.dart      # 8 位数字 → 农历/公历解析
      age_calculator.dart        # 公历/农历周岁计算
      next_birthday.dart         # 未来 N 年推算 + 距今天数
      person.dart                # 人模型
      event.dart                 # 事件模型
      recurrence.dart            # 一次/年/每年农历推算/年手动
    data/
      person_repository.dart      # SharedPreferences
      event_repository.dart
      lab_calendar_provider.dart # 合并数据源
      lab_people_provider.dart
    ui/
      calendar_demo.dart         # DemoPage 入口（slug=calendar，保留）
      month_view.dart
      week_view.dart
      year_view.dart
      day_view.dart
      day_detail_sheet.dart      # 替换原 CalendarDayEventSheet
      person_detail_page.dart
      person_form_sheet.dart
      event_form_sheet.dart
      annual_report_page.dart
      widgets/
        pill_segmented.dart
        month_grid.dart
        day_cell.dart
        lunar_label.dart
        person_chip.dart
        empty_state.dart
```

变更：
- 删除：`LabCalendarEvent` 旧定义（迁移到 `domain/event.dart`）
- 保留：旧 widget 同步逻辑（`CalendarWidgetService` 接口），桌面 widget 不重构
- 新增：人、详情页、年视图、年度报表

## 3. 数据模型

### Person
```dart
class Person {
  final String id;             // uuid
  final String name;           // 姓名/昵称
  final PersonRelation relation; // self | family | friend | colleague | other
  final String? avatarEmoji;   // 单 emoji 头像
  final String? note;
  final DateTime createdAt;
}
```

### EventType 枚举
`birthday | anniversary | countdown | holiday | task | custom`

### CalendarSystem
`solar | lunar`（每个事件独立决定）

### Recurrence
- `none`：一次
- `yearly`：每年公历月日
- `yearlyLunarAuto`：每年按农历月日自动推到公历（闰月取前月）
- `manual`：每年手动选日（用于"今年提前两天"）

### Event
```dart
class Event {
  final String id;
  final EventType type;
  final String title;
  final CalendarSystem system;
  final int month;                 // 1-12
  final int day;                   // 1-30 (lunar) / 1-31 (solar)
  final int? solarYearOffset;      // 仅 manual
  final Recurrence recurrence;
  final String? personId;
  final ColorTag colorTag;         // 8 色预设（沿用原 palette）
  final String? note;
  final DateTime createdAt;
}
```

### 「生日」语义
**没有独立的"身份证"字段**——8 位数字日期（YYYYMMDD）由用户在新增/编辑 Person 时填一次，自动生成/更新一条 type=birthday 的 Event 关联到该 Person。

`DateOfBirthInput` 组件：
- 输入框只允许 8 位数字（输 `200507` → 显示 `2005-07-?`）
- 旁 `Solar ⇄ Lunar` toggle 决定怎么解析
- 一旦输入即创建/更新 Event

新增一个人 = 填名字 + emoji + 8 位数字 + 历法 toggle + 备注。**4 个动作**。

## 4. 农历引擎

引入 `chinese_calendar: ^0.4.0`（离线 1900–2100）。

`domain/lunar_calendar.dart` 封装一层接口（便于未来替换库或加宜忌）：

```dart
abstract class LunarCalendar {
  SolarDate toSolar(int lunarYear, int lunarMonth, int lunarDay, {bool isLeap});
  LunarDate fromSolar(DateTime solar);
  String zodiacOf(DateTime solar);       // 生肖
  String solarTermOf(DateTime solar);    // 节气（可空返回）
  int daysInLunarMonth(int year, int month, {bool isLeap});
}
class ChineseCalendarAdapter implements LunarCalendar { ... }
```

`next_birthday.dart`：基于 LunarCalendar 推算未来 N 年（默认 10 年）真实公历日期，存为 `List<DateTime>`，供年度报表用。

## 5. 视觉令牌（日式极简，去塑料感）

核心：去除 Material 默认蓝 + Elevation 阴影 + 大圆角；改用 **1px 细线分隔 + 哑光奶白底 + 衬线大字 + 无装饰图标**。

```dart
// paper_palette.dart
class PaperPalette {
  static const bg          = Color(0xFFF7F4EE);  // 哑光奶白（Muji 牛皮纸感）
  static const bgElevated  = Color(0xFFFFFCF5);  // 卡片白
  static const ink         = Color(0xFF1F1B16);  // 墨黑
  static const inkMuted    = Color(0xFF6F6A60);  // 淡墨
  static const inkFaint    = Color(0xFFB8B2A4);  // 雾墨
  static const line        = Color(0xFFE6DFD0);  // 分隔线
  static const today       = Color(0xFFC8553D);  // 朱砂红（当天）
  static const accent      = Color(0xFF8B6F47);  // 茶色（主操作）
  static const highlight   = Color(0xFFE9B44C);  // 黄土（生日高亮）
}
```

**Day Cell 重做**（关键视觉）：
```
┌────────────────────┐
│       12           │  ← 公历日期 18pt 衬线
│     七月十二       │  ← 农历小字 10pt 雾墨
│                    │
│      ◯ ─ ◯         │  ← 头像/事件圆点堆叠，最多 3 个 + "+N"
└────────────────────┘
```
- 当天：朱砂红数字 + 1px 朱砂描边外圈（**不填充**——避免塑料感）
- 生日：黄土小圆点贴角
- 农历节日：节字小角标
- 周末：墨黑数字，**不变红**（日式感不靠颜色强语义）

## 6. 视图与交互（按 4 条原则逐项落实）

### 6.1 顶部 Pill Segmented Control — 视图切换 0 弹层
```
[ 今天 ] [ 月 ] [ 周 ] [ 年 ] [ 人 ] [ 报表 ]
```
- 左右滑动整页切换（PagerView）
- pill 状态：底色 bgElevated，激活态底色 ink + 白字，**不用蓝色**

### 6.2 月视图（主）
- **长按日期 = 新建事件**：弹出 inline 速记条（不弹层）：标题 1 行输入，颜色自动按 type 分配
- **点日期 = 看**：底部 sheet 显示当天事件 + 关联人
- **点已有事件 = 编辑**：同一 sheet 滑入详情模式，**不弹新层**
- **快速跳月**：左右滑（PageView） + 顶部「2026年7月」点按弹 mini year picker（不弹独立页面）
- **生日 ribbon**：连续 5 天内有生日，顶部 ribbon 提示「3 天后 妈妈 农历生日」
- **回家**：AppBar 左侧 ⌂ 直接跳回

### 6.3 周视图 / 日视图
- 周视图：7 列纵向时间轴，左侧今天刻度 + 红点
- 日视图：当日事件 timeline + 关联人卡片
- 顶部"今天"pill 始终可见

### 6.4 年视图
- 3×4 网格，每个月一张缩略月历
- 生日/事件高亮用小圆点 + 颜色编码
- 年视图本身**直接可点击单日**（双层联动）

### 6.5 人视图（卡片瀑布）
- 按 relation 分组：自己 / 家人 / 朋友 / 同事
- 每个 PersonCard：emoji 头像 + 姓名 + 关系 + 距下次生日 N 天 / 农历月日
- 顶部「+」直接打开 inline 表单（**不弹层**）
- 点 PersonCard → 详情页（Hero 转场）

### 6.6 人物详情页
- 大头像 + 姓名 + 关系 + 年龄（自动算）
- 生日卡片：公历 + 农历 + 生肖 + 距下次 N 天 + 未来 10 年日期表
- 备注区（可编辑）
- 关联事件列表
- 长按编辑；底部「删除」二次确认（**不弹层**，inline 展开）

### 6.7 年度报表
- 顶部：今年生日总数 + 关系分布（环形图，无 Material 蓝）
- 主体：12 个月卡片流，每月事件 + 关联人 + 农历推算

### 6.8 交互原则检查表

| 场景 | 当前 | 改造后 | 通过哪条 |
|------|------|--------|----------|
| 新建事件 | 加号 → 弹层 → 表单 | 长按日期 → inline 速记 | 快、少点击 |
| 编辑事件 | 点 → 弹层 → 表单 | 点已有事件 → 同一 sheet 滑入详情 | 快、少点击 |
| 新增人 | 按钮 → 弹层 → 表单 | inline 表单卡片直接展开 | 快、少点击 |
| 看今天 | 找不到 | AppBar ⌂ 一键 | 快 |
| 月视图信息 | 只看月日 | 公历+农历+生肖+人+事件+倒计时 | 丰富 |
| 选月份 | 点翻页按钮 | 左右滑 + mini year picker | 准（一个动作） |
| 多人同日生日 | 列表 | ribbon + 头像堆叠 | 丰富、准 |

## 7. 风险与不做事项

**不做（YAGNI）**：
- ❌ 系统通知/提醒（用户明确不要）
- ❌ 桌面 widget 同步重构（保留旧能力）
- ❌ 干支、宜忌（用户明确不要）
- ❌ 多账号/云同步
- ❌ 图片头像（用 emoji 替代）
- ❌ 节气横条（只作为农历月日小字）

**风险**：
- `chinese_calendar` 包维护状况 / 兼容性 — adapter 层缓解
- 1900–2100 外生日 → 优雅降级（提示"超出支持范围，按当前历法保留"）
- 闰月农历生日 → 默认取前一个月同日，UI 提示"今年跳过闰月"
- 字体加载失败 → google_fonts 已有降级到系统字体

**测试**：domain 层单测覆盖 lunar 推算 + age + next_birthday 三组核心逻辑。

## 8. 实施顺序（写入 plan 时细化）

1. 引入 chinese_calendar + adapter
2. 抽出 theme 令牌
3. 拆 domain 层（Person / Event / Recurrence）
4. 拆 data 层（Repository + Provider）
5. 重做月视图 + 新 Day Cell
6. 加人物详情 / 表单 / 人视图
7. 加周视图 + 日视图
8. 加年视图 + 年度报表
9. domain 单测
10. 手动 smoke + 样式 polish