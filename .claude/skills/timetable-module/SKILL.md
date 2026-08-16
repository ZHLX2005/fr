---
name: timetable-module
description: 时间课表模块设计与扩展指南。当用户要求扩展时间课表（新增模式/数据源适配器/DSL 语法/显示配置/追剧功能/多空间/剧模型）、修改 lib/core/timetable/ 或 lib/core/storage/hive/timetable_repository.dart、讨论课表 DSL/周期事件可视化时触发。核心思想：模式只是 DSL 生成器预设，渲染由 config 驱动；追剧模式是剧模型 SSOT 自动派生；扩展优先走适配层与生成器，不碰渲染层。
---

# 时间课表模块扩展指南

> 本 skill 是 lib/core/timetable/ 模块的"事实架构 + 扩展点"速查。
> 完整设计文档：`docs/superpowers/specs/2026-08-15-timetable-module-design.md`
> DSL 规范：`lib/core/timetable/DSL_FORMAT.md`
> 依赖 skill（新 skill 运行时前置）：flutter-work-flow, flutter-hive-workflow
> 如任一前置无法加载，先提示用户再动手。

## 核心思想（一切扩展围绕它）

**所有模式（学校/通用/追剧）只是"生成标准 DSL 的预设"。**
渲染/存储不感知模式，只感知 DSL 产出的 config + 课程。

```
数据来源预设(模式) → DSL 文本 → parseDsl → TimetableConfig + CourseItem[] → 渲染/存储
```

- 新增模式 = 新增 DSL 生成器 + 设置页入口，**渲染层 0 改动**
- DSL 导出/导入 = 完整配置迁移载体（config 段自动携带）
- 追剧模式例外增强：**剧模型是 SSOT**，DSL 由模型自动派生（见 [[anime-mode]]）

## 模块地图

```
lib/core/timetable/
├── domain/models.dart                # TimetableConfig(显示配置全字段)/CourseItem(visibleInCycles 核心)
│                                     #   默认配置: 7天/5节/20周期; isSchoolMode/isAnimeMode 互斥
│                                     #   maxSlotsPerDay=64(fr28 高 slots: 追剧每部剧独占 slot)
├── data/timetable_repository.dart    # 抽象接口(多空间方法族 + loadAnimeSeries/saveAnimeSeries)
├── presentation/
│   ├── timetable_store.dart          # Riverpod SSOT + 空间切换 + 剧模型CRUD(自动派生DSL) + exportToDsl
│   ├── timetable_page.dart           # 主页面(头部空间选择器/_SlotLabel 三模式/每页行数视口纵向滚动)
│   ├── cell_actions/                 # ★ cell 操作策略模式(fr 28)
│   │   ├── cell_action_manager.dart  #   CellActionManager.strategyFor 路由 + CellActionStrategy 抽象
│   │   │                             #   + CellActionContext/CellTarget
│   │   ├── school_cell_actions.dart  #   课表模式: 课程编辑对话框(课程名/地点/老师)
│   │   └── anime_cell_actions.dart   #   追剧模式: 剧模型编辑 + 覆盖风险引导
│   ├── timetable_cell.dart           # 单元格(同 cell 多课程 + 周期过滤)
│   └── timetable_colors.dart
├── service/config/
│   ├── timetable_settings_page.dart  # 主设置页(第一层: 模式三选 + 起始日期 UX + 数据来源 + 高级入口)
│   ├── timetable_advanced_settings_page.dart # 高级设置独立页(周期策略驱动/左侧指示/显示视口/DSL管理)
│   ├── advanced/                     # ★ 三模式策略分离(fr 30)
│   │   ├── cycle_config_strategy.dart #  CycleConfigStrategy 抽象 + 课表(天数固定7)/通用(全可调)/
│   │   │                               #  番剧(模型派生关手动) 三策略 + cycleStrategyFor 路由
│   │   └── shared/zen_controls.dart   #  ZenSegmentButton/ZenConfigSlider/ZenFixedLabel/ZenActionButton
│   ├── timetable_dsl_parser.dart     # DSL 解析(config 段 + w 范围)
│   ├── anime_dsl_generator.dart      # 追剧生成器(纯函数) + AnimeSeriesDraft(剧模型) + 反推
│   │                                 #   episodes=null=长期番填满, 不撑周期数(fallbackCycles)
│   ├── anime_source_adapter.dart     # ★ 适配层(AnimeDraft + kAnimeSourceAdapters 登记
│   │                                 #   含 Bangumi/AniList/SelfHostedAnimeAdapter)
│   ├── timetable_anime_import_dialog.dart  # 番剧来源导入(追加进剧模型)
│   └── timetable_anime_editor_page.dart   # ★ 垂直排期编辑页(剧模型 CRUD, DSL 只读预览)
└── DSL_FORMAT.md
存储: lib/core/storage/hive/timetable_repository.dart(多空间+default 零迁移+
      timetable_anime_series box)
```

## 扩展 SOP

### E1 新增数据源适配器（最常用，水平适配器方向）
→ 见 [[anime-mode]] 适配层节（AnimeSourceAdapter 接口 + kAnimeSourceAdapters 登记 + PeriodicEventDraft 泛化方向）

### E1b 新增模式的 cell 编辑 UI（cell_actions 策略模式，fr 28）

1. `cell_actions/` 新增 `XxxCellStrategy implements CellActionStrategy`（openEditor 实现该模式的编辑 UI 与数据通路）
2. `CellActionManager.strategyFor` 登记模式分支
3. timetable_page **零改动**（只调 `_cellActions.openEditor`）；新触发（长按菜单等）通过 CellTarget 扩展

### E1c 新增模式的高级设置周期配置（cycle_config_strategy，fr 30）

1. `advanced/cycle_config_strategy.dart` 新增 `XxxCycleStrategy extends CycleConfigStrategy`
   （声明 fixedDaysPerCycle / maxSlotsPerDay / allowsManualConfig / hint）
2. `cycleStrategyFor(config)` 登记模式分支
3. 高级设置页 **零模式分支**（周期配置区由策略 buildCycleSection 驱动，_save 用 resolveDaysPerCycle）
4. 模式级配置 UI 控件共用 `advanced/shared/zen_controls.dart`

### E2 新增模式（与学校/通用/追剧平级）
1. `TimetableConfig` 加模式标志字段 + repo save/load 各一行 + settings 模式选择器四选
2. 新建 DSL 生成器纯函数（复用 buildAnimeDsl 结构：时间分组/对齐周一/周期自适应/输出可回灌 DSL）
3. 设置页数据来源区加入口；若该模式需要模型化（如剧模型），参照 [[anime-mode]] 的 SSOT 模式（模型 CRUD → store 自动派生）
4. 渲染层不动

### E3 新增 DSL 语法
- 单点改 timetable_dsl_parser.dart + 同步 DSL_FORMAT.md
- 向后兼容：新语法可选、缺省回退（参考 w2-16 范围语法的加法定式：parse + format 对称）

### E4 新增显示配置
- TimetableConfig 字段 + repo 读写 + 高级设置页 + `slotLabel()` 路由 + DSL config 段参数
- 存储是 untyped Map，加字段天然向前兼容
- 注意：非常用数字配置一律进高级设置独立页，不进主设置页

## 关键机制（勿破坏）

| 机制 | 位置 | 破坏后果 |
|---|---|---|
| 同 cell 多课程 + visibleInCycles 周期过滤 | cell 渲染/cycleGridProvider | 换课/追剧期数失效 |
| 模式互斥三选 | settings isSchoolMode/isAnimeMode | 模式串扰 |
| 追剧自动派生顺序：updateConfig → clearAllItems → upsertItems | store.autoApplyAnimeDsl | 越界课程被删/新旧混存 |
| config 段必须在课程行前 | parser 单遍扫描 | slots 约束失效 |
| DSL 回灌闭环（生成→解析一致） | generator + parser | 导入导出失真 |
| default 空间=旧 box 直读 | repo 路由 | 迁移风险/数据丢失 |
| 剧模型是唯一 SSOT（非 DSL 快照） | store.animeSeries | 剧变更丢失/覆盖 |
| cell 编辑按模式路由（cell_actions 策略） | CellActionManager.strategyFor | 追剧直接编辑课程会被自动派生覆盖 |
| 高 slots 底层支持（maxSlotsPerDay=64） | models/TimetableConfig | 追剧每部剧独占 slot 溢出 |
| 每页行数视口 + 网格纵向滚动 | timetable_page rowsPerPage/slotsPerPage | 高 slots 下首屏行不可达 |
| 周期配置三模式策略（通用天数可调/课表固定7/番剧派生） | advanced/cycle_config_strategy | 通用模式天数被锁 7 天 / 番剧手动配置与模型派生冲突 |
| 长期番不撑周期数（episodes=null → visibleInCycles=null + fallbackCycles） | buildAnimeDsl | 年番把课表周期撑爆 |

## 错误案例

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| 修改渲染层来实现新模式 | 多模式 if-else 蔓延，模块腐化 | 模式=生成器预设，渲染由 config 驱动 |
| 适配器绕过 AnimeDraft 直接造 CourseItem | 丢失缺省字段语义（time 缺失无法提示） | 统一走 AnimeDraft → 排期页补齐 → buildAnimeDsl |
| 大段替换设置页后不 analyze | 括号/缩进错乱编译失败 | 大段编辑后立即 flutter analyze |
| 新 box 忘记注册 StorageRegistry | 存储分析面板看不到 | init() 四件套：guard+adapter+open+register |
| test/ 新增测试不 git add -f | 测试没提交 | test/ 被 .gitignore 忽略，需 -f |
| DSL 只导出课程不带 config 段 | 配置丢失 | exportToDsl 始终携带 config 段 |
| 常用配置堆进主设置页 | 设置页膨胀 | 非常用数字配置进高级设置独立页 |
| 把起始日期塞进高级设置页 | 课表 UX 断链（用户要求回移第一层） | 起始日期是课表模式 UX 自动化（通用直选/学校对齐周一），永远留在主设置页 |
| 用 if(isSchoolMode) 分支控制周期配置可调性 | 通用模式天数被锁 7 天 | 三模式策略分离（cycle_config_strategy），页面零分支 |
| 用 PowerShell Set-Content 改写含中文的 dart 文件 | 中文注释/文案乱码（编码破坏） | 大段替换用 edit 工具；必须脚本改时用 UTF8 读 + 无 BOM UTF8 写 |

## 验证

- `flutter analyze`（基线 197 issues，无新增）
- `flutter test test/core/timetable/anime_dsl_generator_test.dart test/core/timetable/timetable_dsl_config_test.dart`（生成器/w 范围/反推/回灌/序列化）
- 改动存储/原生后按 flutter-work-flow 要求验证

## 引用索引（按需加载）

| ref | 何时读取 | 路径 |
|---|---|---|
| [[anime-mode]] | 扩展/修改追剧模式（剧模型/适配层/排期编辑器/生成器/反推）时 | references/anime-mode.md |
| [[anime-backend-api-spec]] | 自建新番后端 API 的契约/联调/新增 SelfHostedAnimeAdapter 时 | references/anime-backend-api-spec.md |
