# 时间课表模块设计文档（timetable）

> 版本：2026-08-15（覆盖多空间/DSL 增强/追剧模式/适配层/排期编辑器）
> 定位：本模块正在成为"周期事件可视化"的大模块——课表只是第一个领域。
> 本文档描述**当前事实架构 + 扩展点**，供后续扩展（更多模式/更多数据源适配器）直接使用。

## 1. 核心思想：DSL 是唯一数据驱动层

**所有模式（学校/通用/追剧）说到底只是"生成标准 DSL 的预设"。** 课表渲染/存储不感知模式，
只感知 DSL 产出的 config + 课程。显示层由 config 驱动（行列/左侧指示/开始日期）。

```
数据来源预设(模式) → DSL 文本 → parseDsl → TimetableConfig + CourseItem[] → 渲染/存储
```

- 模式切换 = 换一个 DSL 生成器；DSL 导出/导入 = 完整配置迁移载体
- 新增模式 = 新增一个"DSL 生成器 + 设置页入口"，**不碰渲染层**
- **追剧模式增强（fr 27）**：剧模型是 SSOT，DSL 由模型自动派生——
  剧 CRUD 变更即自动重算并应用，无手动生成/预览/覆盖；API 导入=追加进模型

## 2. 分层结构

```
lib/core/timetable/
├── domain/models.dart                  # TimetableConfig / CourseItem / TimetableMappers
│                                       #   config 全部显示配置字段（含 leftLabelMode 等）
├── data/timetable_repository.dart      # 抽象接口（多空间方法族）
├── data/data.dart                      # barrel
├── presentation/
│   ├── timetable_store.dart            # Riverpod SSOT + 空间切换 + exportToDsl
│   ├── timetable_page.dart             # 主页面（头部空间选择器 / _SlotLabel 三模式）
│   ├── timetable_cell.dart             # 单元格（同 cell 多课程 + 周期可见过滤）
│   ├── timetable_editor_dialog.dart    # 课程编辑
│   ├── cycle_visibility_selector.dart  # 周期可见性
│   └── timetable_colors.dart           # 莫兰迪配色（与系统主题隔离）
├── service/config/
│   ├── timetable_settings_page.dart    # 主设置页（第一层：模式三选/起始日期 UX/数据来源/高级入口）
│   ├── timetable_advanced_settings_page.dart # ★ 高级设置独立页（周期策略驱动/左侧/显示视口/DSL管理）
│   ├── advanced/                       # ★ 三模式策略分离（fr 30）
│   │   ├── cycle_config_strategy.dart  #   课表(天数固定7)/通用(天数可调1-7)/番剧(模型派生关手动)
│   │   └── shared/zen_controls.dart    #   Zen 共享控件（SegmentButton/ConfigSlider/FixedLabel/ActionButton）
│   ├── timetable_dsl_parser.dart       # DSL 解析（config 段 + 课程行 + w 范围）
│   ├── timetable_import_dialog.dart    # DSL 导入（自动应用 config 段）
│   ├── timetable_week_calculator.dart  # 周一对齐/周数推算
│   ├── sicau_import_dialog.dart        # 学校模式数据源（教务）
│   ├── anime_dsl_generator.dart        # 追剧生成器（纯函数）+ AnimeSeriesDraft 剧模型 + 反推
│   ├── anime_source_adapter.dart       # ★ 开放 API 适配层
│   ├── timetable_anime_import_dialog.dart # 番剧来源导入对话框
│   └── timetable_anime_editor_page.dart  # ★ 垂直排期编辑页（剧模型 CRUD，DSL 只读预览）
└── DSL_FORMAT.md                       # DSL 格式规范（与代码同步维护）
```

存储实现不在模块内：`lib/core/storage/hive/timetable_repository.dart`
（Hive + 多空间 + `timetable_anime_series` box）。

## 3. 数据模型

### TimetableConfig（存储：untyped Map box，加字段天然向前兼容）

| 字段 | 说明 |
|---|---|
| startDateIso / cycleCount / daysPerCycle / slotsPerDay | 网格基础（默认 7天/5节/20周期） |
| isSchoolMode / isAnimeMode | 模式标志（互斥，settings 三选一） |
| leftLabelMode | 0=序号 1=时间段 2=自定义 |
| slotLabels / slotStartTimes / slotDurationMin / leftWidth | 左侧指示显示配置 |
| backgroundImagePath / id / updatedAt | 其它 |

### CourseItem（cellKey = `d{dayOfCycle}_s{slotIndex}`，同 cell 支持多课程）

| 字段 | 说明 |
|---|---|
| dayOfCycle / slotIndex | 周期内定位（所有周期重复显示） |
| visibleInCycles | **null=全部周期；否则只在这些周期显示**（换课/追剧期数的核心） |
| title / location / teacher / colorSeed | 展示字段 |

## 4. DSL 规范（完整见 DSL_FORMAT.md）

```text
# 可选 config 段（必须放课程行前）
config: days=7 slots=5 cycles=16 start=2026-08-15 mode=anime left=1 duration=45

# 课程行：课程名 @ 星期(1-7) 节次 [w周次范围] [位置] [教师]
剧A @ 6 1 w1-10 11:00 更新 · 10期
```

- **config 段**表达行数/列数/开始时间/模式/左侧指示；`slots` 同时约束课程行节次范围
- **w 范围语法** `w2-16`（支持混用 `w1-3,5`；导出自动压缩连续范围）——追剧期数表达的基石
- `parseDsl` 返回 `DslParseResult{courses, errors, config?}`；导入时自动应用 config
- `exportToDsl` 自动携带 config 段 → **导出=完整配置迁移**

## 5. 多空间存储（零迁移兼容）

```
box timetable_config / timetable_items   ← default 空间（旧数据，直读不改）
box timetable_anime_series               ← default 空间追剧剧模型（key='series'）
box timetable_spaces                     ← 新空间: key=spaceId → {name, config, items, animeSeries}
SharedPreferences: timetable-active-space ← 激活空间 id
```

- `default` 空间永远映射旧 box → 既有数据零迁移
- repo 接口：listSpaces/createSpace/renameSpace/deleteSpace/setActiveSpace +
  按激活空间路由的 load/save + loadAnimeSeries/saveAnimeSeries（剧模型）
- store：spacesProvider（FutureProvider）+ setActiveSpace(→re-hydrate) + 剧 CRUD（自动派生 DSL）
- 四个 box 均注册 StorageRegistry（存储分析面板可见）

## 6. 模式系统（= DSL 生成器预设）

| 模式 | 数据来源（第一层） | 生成器 | 配置入口 |
|---|---|---|---|
| 学校 | SICAU 教务导入 | 服务端 DSL → parseDsl | 设置页数据来源区 |
| 通用 | 手填/DSL 导入 | 手动 | 高级设置页 |
| 追剧/番 | Bangumi API / 手工 | `buildAnimeDsl`（纯函数） | ★ 垂直排期编辑页（剧模型 CRUD） |

**剧模型 SSOT（fr 27）**：追剧模式的唯一数据源 = `AnimeSeriesDraft[]`（存储于
`timetable_anime_series` box / 空间 record 的 animeSeries 字段）。剧 CRUD
（add/update/delete/import 追加）→ store 自动 `buildAnimeDsl` 派生 config+课程并应用，
**无手动生成/预览/覆盖**；排期编辑页只读展示派生 DSL。

追剧生成算法（anime_dsl_generator.dart，纯函数可测）：
1. 播出时间分组 → 竖直 cell（slotIndex）
2. 起始日期 = 最早开播日对齐周一
3. visibleInCycles = [开始周 .. 开始周+期数-1]
4. cycleCount = 最长覆盖（自动膨胀/收缩）
5. 输出 config + items + DSL（可回灌 parseDsl 还原，有单测）

## 7. ★ 扩展点清单（后续扩展直接在此插入）

### E1 新增数据源适配器（水平适配器方向）
```dart
// anime_source_adapter.dart
abstract class AnimeSourceAdapter {
  String get id;
  String get label;
  Future<List<AnimeDraft>> fetch();
}
// 登记：kAnimeSourceAdapters = [BangumiCalendarAdapter(), 新Adapter()];
```
新来源只需实现 fetch()（AnimeDraft: title/startDateIso/weekday/time/episodes/sourceUrl，可缺省）。
导入对话框自动出现来源下拉。**水平扩展方向**：AnimeDraft 泛化为 PeriodicEventDraft
（周期性事件：直播/比赛/日程/课程表/影视更新时间），适配器跨领域复用。

### E1c 高级设置周期配置策略（fr 30）

三模式周期配置平级策略（`advanced/cycle_config_strategy.dart`，仿 CellActionManager 模式）：

| 策略 | fixedDaysPerCycle | allowsManualConfig | maxSlotsPerDay |
|---|---|---|---|
| SchoolCycleStrategy（课表） | 7（固定） | true | 6 |
| GeneralCycleStrategy（通用） | null（1-7 可调） | true | 6 |
| AnimeCycleStrategy（番剧） | 7 | false（剧模型派生，显示 hint） | 64 |

- 页面零模式分支：`cycleStrategyFor(config)` 路由 → `buildCycleSection` 驱动 UI，`resolveDaysPerCycle` 决定保存值
- 模式级配置 UI 共用 `advanced/shared/zen_controls.dart`（ZenSegmentButton/ZenConfigSlider/ZenFixedLabel/ZenActionButton）
- 教训：此前 `if(isSchoolMode)` 硬编码分支把通用模式天数锁 7 天

### E2 新增模式
1. `TimetableConfig` 加模式标志字段（+ repo save/load 一行 + settings 四选一按钮）
2. 新增"DSL 生成器"纯函数（复用 buildAnimeDsl 模式）
3. 设置页数据来源区 + 入口按钮
4. 渲染层 0 改动（显示由 config 驱动）

### E3 新增 DSL 语法
- parser 单点修改（timetable_dsl_parser.dart）+ DSL_FORMAT.md 同步
- 向后兼容原则：新语法可选、缺省回退

### E4 新增显示配置
- TimetableConfig 字段 + repo 读写 + settings 高级功能区 + `slotLabel()` 路由 + DSL config 段参数

## 8. 已验证的关键机制（勿破坏）

- 同 cell 多课程 + visibleInCycles 周期过滤 = 换课/追剧期数的基础
- 模式互斥三选（isSchoolMode/isAnimeMode）
- 追剧自动派生流程（store._autoApplyAnimeDsl）：updateConfig（含 leftLabelMode=1 + slotStartTimes）→ clearAllItems → 按 cellKey upsert；剧变更即触发
- DSL 回灌闭环（生成 → 解析 → 还原一致，单测保证）
- 反推开始日期：`backfillStartDate(当前期数, 星期)` 从最近播出日回推 (期数-1) 周
- 剧模型序列化往返（AnimeSeriesDraft toJson/fromJson，缺字段回退默认）

## 9. 测试

- test/core/timetable/anime_dsl_generator_test.dart（生成器/w 范围/反推/回灌）
- test/core/timetable/timetable_dsl_config_test.dart（config 段/三模式/时间进位）
- test/core/timetable/start_date_resolver_test.dart、week_calculator_test.dart
- ⚠️ test/ 被 .gitignore 忽略，新增测试需 `git add -f`

## 10. 坑（本模块历史教训）

| 坑 | 后果 | 预防 |
|---|---|---|
| 设置页括号/缩进错乱 | 编译错误 | 大段替换后先 analyze |
| config 段在课程行之后 | slots 不约束课程 | config 段必须置顶；parser 单遍扫描 |
| updateConfig 顺序（先 config 后导入） | 越界课程被删 | 追剧先 updateConfig 再 upsertItems |
| DSL 只导出课程不含 config | 配置丢失 | exportToDsl 始终携带 config 段 |
| 新 box 忘注册 StorageRegistry | 存储分析面板看不到 | init() 内四件套含注册 |
