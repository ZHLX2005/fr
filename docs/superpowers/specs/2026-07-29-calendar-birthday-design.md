# 日历生日历法 — Source of Truth 升级

日期: 2026-07-29
状态: 设计待用户复核

## 背景与问题

日历 demo 的「人物生日」目前由 `Event(personId, type=birthday)` 间接承载,公历/农历的判定存放在 `Event.system`,`month/day/lunarAnchorYear` 在 `_save()` 中经过 `公历 → lunar 反推` 二次编码才入库。

实际表现:

- 用户输入农历日期,表单回显时再次经过「反推回公历 → 再 lunar」,**最终显示的字符串可能与输入时不一致**(尤其是闰月 / `lunarAnchorYear` 漂移到 `from.year` 的场景)。
- 重新进入表单,日期已经变了 —— 不可作为「确定的生日」使用。

## 设计目标

1. **用户原始输入即 source of truth**,不做后端 round-trip。
2. 公历与农历两种输入都能定位到唯一日期(互转无歧义)。
3. 切换历法 chip 时,日期字符串换算稳定不漂移。
4. UI 流畅:实时预览,保存后重新打开内容一致。

## 数据模型

### `Person` 升级(新增 3 字段,迁移友好)

```dart
class Person {
  final String id;
  final String name;
  final PersonRelation relation;
  final String? avatarEmoji;
  final String? note;
  final DateTime createdAt;

  // ↓ 新增:source of truth
  final DateTime birthSolar;        // 公历真值锚点(1900-2100)
  final LunarDate birthLunar;       // 用户原始输入的农历月日(含闰月)
  final CalendarSystem birthSystem; // 用户最后选定的历法(UI 回显)
}
```

`birthSolar` 与 `birthLunar` 必须严格一致(互为同一日期的两种历法表示)。`birthSystem` 仅用于 UI 回显,不影响后续计算。

`PersonAdapter` 升级为 v2:读取老记录(无新字段)时,根据该 Person 的 birthday Event 一次性反推填充,然后调用 `update()` 回写,后续走新字段。

### `Event` 继续保留(派生而非源)

- `Event(personId, type=birthday)` 仍然存在,但**只在 Provider 层由 `Person.birthSolar/birthLunar/birthSystem` 派生生成**。
- `Event.system` / `recurrence` / `lunarAnchorYear` 都由派生规则决定,不再由表单直接写入。

`NextBirthdayResolver._lunarUpcoming` 修改:`lunarAnchorYear` 缺失时回退到 `birthSolar.year`(而不再是 `from.year`),消除「from.year 已过导致漂移」的隐患。

## UI 流程

### `PersonFormSheet` 重构

```
┌──────────────────────────────────┐
│ 边框强调卡(姓名/关系预览)         │
├──────────────────────────────────┤
│ 姓名                              │
├──────────────────────────────────┤
│ 历法 chip:  [公历] [农历]         │   ← 切换会重排下方输入框
├──────────────────────────────────┤
│ 公历模式:                          │
│   输入框: YYYY-MM-DD              │
│ 农历模式:                          │
│   输入框: YYYY 年 [闰月?] MM-DD    │
├──────────────────────────────────┤
│ 预览(实时):                       │
│   公历 → 「农历 X 年闰 Y 月 Z 日」  │
│   农历 → 「公历 X-Y-Z」            │
├──────────────────────────────────┤
│ 关系 chip                          │
│ 备注                               │
│ [保存]                             │
└──────────────────────────────────┘
```

切换 chip:

1. 把当前输入按当前历法解析为 `DateTime solar`。
2. 把 `solar` 反算为对方历法的字符串,替换输入框内容。
3. 刷新预览。

整条链路是 `solar` 单向锚定,无 round-trip 漂移。

保存:

1. 校验输入合法性(闰月存在?/ 公历在 1900-2100 之间?)
2. `Person.birthSolar/birthLunar/birthSystem` 三件套落库
3. Provider 删旧 birthday Event,按新三件套派生一条新 Event

## 派生 Event 规则

```
system = person.birthSystem
recurrence = system == solar ? Recurrence.yearly : Recurrence.yearlyLunarAuto
month/day = (system == solar)
  ? (solar.month, solar.day)
  : (lunar.month, lunar.day)
year = solar.year  // 用于首次发生年参考
lunarAnchorYear = solar.year  // 恒等于真值,不再依赖 from.year
```

`NextBirthdayResolver._lunarUpcoming` 修改为:

```dart
final sAnchor = _cal.toSolar(anchorLunarYear, e.month, e.day);
```

其中 `anchorLunarYear` 现在恒等于 `birthSolar.year`,**保证稳定**。

## 错误处理

- 农历月日不在该年实际月份内(如平 4 月写 30 日,或闰月写错月份) → 输入框下方红字提示「该月仅 X 天」/「该年无闰 X 月」,保存按钮禁用。
- 公历超出 1900-2100 范围 → 提示且禁用保存。
- 切换 chip 时反算失败(理论不应发生) → 输入框清空 + 提示。

## 迁移策略

1. 老 Person 无新字段 → 第一次进入表单时,按其 birthday Event 反推填充 3 个新字段,然后 `update()` 回写。
2. 老 Event 保留到下一次保存时由 Provider 删除 + 重建,期间所有读路径(`NextBirthdayResolver` / PeopleView / AnnualReport)优先用新字段,缺失时回退到 Event。
3. `PersonAdapter` 读 v1 记录:缺新字段 → 走 Event 反推;读 v2 记录:直接用新字段。

## 测试要点

1. **稳定回归**:保存农历生日 → 关闭 → 重开 → 输入框内容 == 保存时输入(精确匹配字符串)。
2. **切换稳定**:连续切换公历↔农历 5 次,公历真值不漂移。
3. **闰月**:输入「2024 闰 2 月 15 日」→ 预览显示对应公历 → 保存 → 重开 → 闰月 toggle 仍正确。
4. **迁移**:老数据(只有 Event)新建 Person → 打开表单 → 字段已自动填好且能切换 chip。
5. **NextBirthdayResolver**:跨年触发(今天是 2026-12-31,生日农历腊月)→ 推算到 2027 公历对应日正确。

## 影响范围

| 文件 | 改动 |
|------|------|
| `lib/lab/demos/calendar/domain/person.dart` | 加 3 字段 + copyWith + toJson + fromJson 迁移 |
| `lib/lab/demos/calendar/data/person_adapter.dart` | typeId 升 v2,反序列化兼容老记录 |
| `lib/lab/demos/calendar/ui/person_form_sheet.dart` | 全面重构输入 + 预览 + chip 切换 |
| `lib/lab/demos/calendar/data/lab_calendar_provider.dart` | 新增 `upsertBirthdayFor(person)` 派生 Event |
| `lib/lab/demos/calendar/domain/next_birthday.dart` | lunarAnchorYear 缺省回退到 solar 真值 |
| `lib/lab/demos/calendar/ui/people_view.dart` | 展示用新字段(Event 仅作兜底) |