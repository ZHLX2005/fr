# 日历视图优化 — 意图文档

> 来源：kvcli todo `fr` 主题 task #27、#43
> 日期：2026-08-17
> 状态：已确认 → 等待 writing-plans 产出实现计划

## 主题

`lib/lab/demos/calendar/ui/month_view.dart` + `lib/lab/demos/calendar/ui/widgets/day_cell.dart` 的视觉增强，让"回到今天"更显眼、所有有事件的天都有指示。

## 任务清单

| ID  | 原文                                                                       | 润色                                                                                          |
| --- | -------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| 27  | celandar模块，支持快速回到当前所在月                                       | 月视图头部：仅当 `viewMonth != 当月` 时，在年月标题旁显示"今天"药丸按钮，点击后 `jumpToday()` |
| 43  | 日历，对于有事件的天数，月日历的那天需要添加一些指示呀                     | DayCell 在日期数字下方加 4px 彩色小圆点，按当天事件的 `colorTag` 取色（多事件横排）           |

## 上下文摘要

- 当前 `MonthView` 已有 `GestureDetector(p.jumpToday)` 绑在标题文字上，但无视觉提示，**用户不知道能点**
- 当前 `DayCell` 已有：生日 → 右上 4px 黄土点；带 personId 的事件 → 底部头像堆叠
- **缺口**：非生日 + 无 personId 的事件（anniversary/countdown/holiday/task/custom）**完全无指示**
- 现有 `Event.colorTag` 8 色预设（`lib/lab/demos/calendar/domain/event.dart:10`），含 hex，可直接渲染

## 目标

1. **Task 27**：在月视图头部加条件显示的"今天"药丸按钮，仅在非当前月时浮现，让"快速回到今天"显而易见；当前月时按钮隐藏
2. **Task 43**：DayCell 加底部彩色小圆点，覆盖所有事件类型；与已有指示（生日点、头像堆叠）共存不冲突

## 边界

**范围内**：
- MonthView 头部布局微调
- DayCell 新增底部小圆点
- 复用 `Event.colorTag.hex`（无需新枚举/字段）
- 复用现有 `PaperPalette` 色板

**范围外**：
- 列表视图（day_view/week_view）暂不动
- 事件类型颜色重定义、主题色板扩展
- 长按标题弹"选月份"菜单（可后续）
- 农历事件 vs 公历事件区分显示

## 验收标准

### Task 27
- [ ] 当前月（`viewYear == now.year && viewMonth == now.month`）时：**无药丸按钮**（保持原视觉简洁）
- [ ] 翻到非当前月（如 7 月或 9 月）时：标题右侧出现"今天"药丸按钮，**朱砂红文字 + 1px 描边**，无填充（保持纸张风）
- [ ] 点击药丸 → `p.jumpToday()` → 月份跳回当前月 + 药丸自动消失
- [ ] 跨年时同样工作（1 月翻到上一年的 12 月也算"非当前月"）
- [ ] 视觉风格与 PaperPalette 一致，**不引入新色板**

### Task 43
- [ ] 有事件的天（任意 `EventType`），且**无** personId 时：显示底部 4px 彩色小圆点
- [ ] 有事件 + 有人（personId 非空）：**保留原头像堆叠**，彩色小圆点贴角显示（不与头像重叠）
- [ ] 多个事件不同色：圆点横排，间距 2px
- [ ] 邻月日期（`inCurrentMonth=false`）**不显示**任何指示（保持视觉层次）
- [ ] 圆点颜色 = `Event.colorTag.hex`（gray/red/orange/amber/sage/teal/indigo/plum）
- [ ] 生日事件（已有右上黄土点）继续保留，**不重复**显示

## 风险 / 关注点

- DayCell 内部已是 `Stack` + `Column`，底部还有 `LunarLabel`（在 `Center` 内），新增的圆点行需不与现有布局冲突
- `eventsOnDate` 当前已用 `LunarAdapter` 正确处理农历事件，无需改 provider
- 测试：现有 `test/lab/demos/calendar/calendar_provider_ready_test.dart` 与 DayCell 无直接关联，不需改

## 实现入口

- `lib/lab/demos/calendar/ui/month_view.dart` — Task 27 入口
- `lib/lab/demos/calendar/ui/widgets/day_cell.dart` — Task 43 入口
- `lib/lab/demos/calendar/ui/widgets/month_grid.dart` — 给 DayCell 多传一个字段 `eventDots: List<Color>`（解耦：MonthGrid 取色，DayCell 只负责渲染）
- 颜色辅助：`lib/core/theme/paper_palette.dart` 已有 `hex` 解析工具（检查），无则新增 `Color(0xFF${hex})` 一行

## 后续可考虑（不在本次范围）

- DayCell 长按事件预览（弹 sheet 列出当天所有事件）
- 月视图左右滑切换月份（手势）
- 标题长按弹月份选择器
