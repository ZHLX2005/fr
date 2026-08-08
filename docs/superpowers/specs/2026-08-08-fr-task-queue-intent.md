# 2026-08-08 fr 主题任务意图文档

> 消费者：fr（Flutter repo `D:\code\a_dart\prj\fr`）。后端 `todo:prompt:fr` 当时接口超时未取到，
> 本文按代码实际现状 + 用户口述对齐。6 条 open 任务，聚类 4 簇。

## 聚类总览

| 簇 | 任务 | 主题 |
|---|---|---|
| A | id=8、id=10 | kvcli 清单交互（误删防护 / topic 自动收集） |
| B | id=9 | 课表起始日期弹窗 |
| C | id=11、id=12 | clock 模块（历史记录 / track stop） |
| D | id=15 | kvcli 清单归档（克隆 / 冷数据） |

---

## 簇 A · kvcli 清单交互

### id=8 — 快捷 topic 的 ✕ 容易误触导致错删

**原文**：`kv清单 对于列举的topic，ui很容易误触，导致错删除`

**现状（已读代码）**
- `lib/lab/demos/kvcli_todo/kvcli_todo_widgets.dart:93-107`：`KvTopicChip` 的 ✕ = `Icon(size:12)` + `EdgeInsets.all(2)`，热区约 16px（≪ 44px 可点最小尺寸），紧贴 chip 主体，点 chip 回填主题时极易压到。
- `lib/lab/demos/kvcli_todo_demo.dart:286-296` `_deleteTopic()`：**无确认弹窗**，点 ✕ 直接写回 KV，不可撤销。对比：任务删除 `_deleteTask` 有 `showKvTaskDeleteConfirm`（`kvcli_todo_dialogs.dart:125`），topic 删除漏了。

**修复方向**：① ✕ 删除前加确认（对齐任务删除的确认弹窗）；② 放大热区（≥44px）或把删除入口与 chip 主体分离（如长按删除 / 单独小按钮移出点击区）。

**边界**：topic 删除确认取消不删、确认才删并持久化；chip 点击回填主题的行为保持。

**验收**：误触率下降；删除有确认弹窗；确认/取消两条路径持久化一致。

### id=10 — 添加 todo 时，新 topic 自动进入快捷列表

**原文**：`topic事件功能，应该只能记录，如果添加了一个todo，并且没有出现，就自动添加到快捷topic选择里面`

**现状（已读代码）**：`kvcli_todo_demo.dart:169-198` `_add()` 只写 `todo:open`，完全没碰 `_topics` / `todo:topics`。手输新主题提交后不会出现在快捷 chip，下次需重打。

**修复方向**：`_add()` 成功落库后，若 `topic` 不在 `_topics` 且非空 → append 并 `_saveTopics`。

**边界**：topic 已存在 / 为空时不重复加；`_topics` 解析失败兜底为空数组时不破坏提交。

**验收**：手输新主题提交 → 快捷 chip 自动出现该主题；重复提交同主题不重复添加。

---

## 簇 B · 课表起始日期弹窗

### id=9 — 起始日期手动指定，弹窗切换无效

**原文**：`时间课表，通过起始日期和开始日期手动指定，uiux是错误的，出现的弹窗切换无效`

**现状（agent 调查报告）**
- 只有**一个**日期字段 `startDateIso`（`timetable/domain/models.dart:18`），无「起始/开始」两个字段；入口在 `timetable_settings_page.dart:302-380`。
- **切换无效确切根因**：`timetable_week_calculator.dart:33` 创建 `TabController(length:2)` 后**无 addListener**，Tab 内容用 `if (_tab.index == 0)` 条件渲染（:146），未用 `TabBarView` → `build()` 不重跑，点「选日期」Tab 指示器动但下方内容不动。
- **uiux 错误**：同一件事 3 条路径，两条行为相反——点日期卡片走 `WeekCalculatorDialog` 只回填不保存；下方「选日期」按钮 `showDatePicker` 选完**立刻 `_save()`**，而 `_save()` 内有 `Navigator.pop`（`timetable_settings_page.dart:359-360, :82`）→ 整个设置页被关，未保存的滑块改动被静默提交。另：dialog 双层 `Material`+`zenCard()` 重复描边圆角缺口（:87-94）；自绘 `Container(black26)` 遮罩叠在 `showDialog` barrier 上（:80-85）；标题写死「起始日期」但实际是周数推算器。
- 持久化/周期重算链路是通的，纯 UI 层问题。

**修复方向**：① TabController 加 `addListener` 触发重建（或改 `IndexedStack(index:_tab.index)`）；② 收敛两条选日期入口语义——「选日期」按钮去掉自动 `_save`，只回填，与 dialog 路径一致（或统一只走 dialog）；③ 修双层描边缺口、去掉自绘 barrier、标题按实际功能修正。

**边界**：不改数据模型与持久化；不动 SICAU 导入链路。

**验收**：弹窗内 Tab 切换内容即时跟随；两种选日期入口行为一致、都不再整页被关；设置页滑块改动不被静默提交。

---

## 簇 C · clock 模块

### id=11 — 没有 clock 时历史记录整段不显示

**原文**：`clock有bug，如果不存在clock，那么历史记录也都不会再显示`

**现状（agent 调查报告）**：`clocks_tab.dart:67-71` 当 `provider.clocks.isEmpty` 直接 `return _EmptyState(...)`，后面的 Records slivers（:90-109，数据源 `provider.records` 与 clocks 完全独立，`lab_clock_provider.dart:16`）全被吞。record 并非按 clockId 反查过滤（标题是快照），`deleteClock` 也不删 records——数据都在，纯 UI 早退。

**附带退化**：`getRecordLiveDuration`（`lab_clock_provider.dart:517-530`）clock 已删且 record 未 completed 时恒 `return 0` → 时长徽章恒 0s / Today 累加 0 / 侧滑 Create 因 `dur>0` 失效；`deleteClock` 不结算在飞 record。

**修复方向**：① 空状态改为 `CustomScrollView` 里的 `SliverToBoxAdapter`（替代 grid sliver），Records slivers 恒渲染；② `getRecordLiveDuration` 兜底改 `record.accumulatedSeconds` 而非 0；③ `deleteClock` 先结算名下未 completed 的 record。

**验收**：一个 clock 都没有时，历史记录仍完整显示；删掉 clock 后其历史记录时长不丢失。

### id=12 — track 点 Stop 直接白屏退出

**原文**：`clock的track功能，stop之后会直接白屏 然后退出`

**现状（agent 调查报告）**
- **双重 pop**：Stop 按钮手动 `nav.pop()`（`track_runner_page.dart:117-130`）+ 250ms ticker 检测 `activeTrackId==null` 自动 `pop()`（:23-34，`dispose` 才 cancel）。`stopTrack` 里 `await _saveRecords()` 让出事件循环后置 `_activeTrackId=null`（`lab_track_provider.dart:265`）。pop 触发反向过渡动画 300ms，期间 `mounted==true`、ticker 未 cancel → 250ms 内必然再触发一次自动 pop，把内层 `MaterialApp`（`clock_demo.dart:153-217`）的 home route 弹掉 → 内层 Navigator 空 → 白屏 → 整页退出。
- **第二条真实崩溃路径**：`totalRemaining`（`lab_track_provider.dart:49-60`）`:57` 无越界保护；`_advanceSegment` 先 `_currentSegmentIndex += 1` 越界调 `_completeTrack()` 不 await，`_completeTrack` 在 `await _saveRecords()`（:232）后才 `_activeTrackId=null`（:234）→ 间隙里 `notifyListeners` 触发 rebuild 读 `t.segments[length]` → RangeError → build 抛异常白屏。
- 附带：`pauseTrack` 不改 `_activeTrackId`，runner 的 `isPaused = activeTrackId==null`，暂停态 UI 表达不了；`stopTrack` 写 `accumulatedSeconds:0`，停止的 record 实际恒 0s。

**修复方向**：① Stop 处理器里先 `_autoPopped=true; _ticker?.cancel()` 再 pop（单一出口：pop 只走一处）；② `totalRemaining` 加 `if (_currentSegmentIndex >= t.segments.length) return 0;`；③ `_completeTrack` 把 `_activeTrackId=null`/`_timer?.cancel()` 挪到 `await _saveRecords()` 之前；④ 附带修暂停态标志、stop 结算实际秒数。

**验收**：Stop 只 pop 一次正常回列表；skip 末段 / 自然跑完不白屏；暂停态 UI 有表达；停止的 record 时长=实际消耗。

---

## 簇 D · kvcli 清单归档

### id=15 — 已完成项克隆回待办 + 清理到冷数据

**原文**：`对于ve清单，对于已经完成的元素，添加一个按钮，克隆，重新出现到待办里面，再添加一个按钮，清理所有已经完成，作为冷数据，冷数据使用kv清单里面一个新的子key，app不需要能够查询到，已经完成的多半都是冷数据，冷数据的k内部再添加一个日期因素，避免kv被覆盖，后端是支持k的 前缀的xxx：*查询的，所有可以这样去实现`

**意图确认（用户拍板）**
- 原文「ve清单」= **kv 清单** 笔误（正文自己说"kv清单里面一个新的子key"）。
- **冷数据只归档、不需要查看** —— 后端前缀查询方案存在（`user-kv-invitecode` skill）但**不用管**，`KvEndpoint` 无需扩展，直接 `set` 新 key 即可。

**功能拆分**
1. **克隆**：已完成卡片加「克隆」按钮 → 复制为 `KvTask(id=max+1, topic, text, createdAt=now, doneAt='', note='')` 追加进 `todo:open`。
2. **清理已完成到冷数据**：「清理所有已完成」→ 把当前 `todo:done` 整批归档到冷数据 key，然后清空 `todo:done`。
3. **冷数据 key**：形如 `todo:done:cold:<yyyy-MM-dd>`（`KvCliTodoConst` 里加常量），靠日期分片避免覆盖；app 端只 `set` 不 `get`/`list`。

**边界**：克隆保留 topic/text；清理确认弹窗（对齐 `_clearAll` 的确认模式）；冷数据 key 日期用当天，同一天多次清理合并到同一 key（后续清理累加）。

**验收**：克隆后新任务出现在待办列表（id 递增、topic/text 保留）；清理后 done 列表空、冷数据 key 存在且含全部已完成 JSON；不同日期的清理落在不同 key、互不覆盖。

---

## 待办顺序 & 依赖

全部独立、无互相依赖。建议顺序：**簇 A → 簇 C → 簇 B → 簇 D**（bug 先行，纯新增功能殿后）。
每簇解决完按 kvcli 回填 `kvcli todo done <id> --result "..."`。
