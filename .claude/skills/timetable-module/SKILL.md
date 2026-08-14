---
name: timetable-module
description: 时间课表模块设计与扩展指南。当用户要求扩展时间课表（新增模式/数据源适配器/DSL 语法/显示配置/追剧功能/多空间）、修改 lib/core/timetable/ 或 lib/core/storage/hive/timetable_repository.dart、讨论课表 DSL/周期事件可视化时触发。核心思想：模式只是 DSL 生成器预设，渲染由 config 驱动；扩展优先走适配层与生成器，不碰渲染层。
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

## 模块地图

```
lib/core/timetable/
├── domain/models.dart                # TimetableConfig(显示配置全字段)/CourseItem(visibleInCycles 核心)
├── data/timetable_repository.dart    # 抽象接口(多空间方法族)
├── presentation/
│   ├── timetable_store.dart          # Riverpod SSOT + 空间切换 + exportToDsl
│   ├── timetable_page.dart           # 主页面(头部空间选择器/_SlotLabel 三模式)
│   ├── timetable_cell.dart           # 单元格(同 cell 多课程 + 周期过滤)
│   └── timetable_colors.dart
├── service/config/
│   ├── timetable_settings_page.dart  # 设置页(模式三选/数据来源/高级功能折叠)
│   ├── timetable_dsl_parser.dart     # DSL 解析(config 段 + w 范围)
│   ├── anime_dsl_generator.dart      # 追剧生成器(纯函数) + backfillStartDate 反推
│   ├── anime_source_adapter.dart     # ★ 适配层(AnimeDraft + kAnimeSourceAdapters 登记)
│   ├── timetable_anime_import_dialog.dart  # 番剧来源导入
│   └── timetable_anime_editor_page.dart   # ★ 垂直排期编辑页(纯剧语言)
└── DSL_FORMAT.md
存储: lib/core/storage/hive/timetable_repository.dart(多空间+default 零迁移)
```

## 扩展 SOP

### E1 新增数据源适配器（最常用，水平适配器方向）
1. 在 anime_source_adapter.dart 实现 `AnimeSourceAdapter`（id/label/fetch → List<AnimeDraft>）
2. 加入 `kAnimeSourceAdapters` 列表 → 导入对话框自动出现来源下拉
3. 水平泛化方向：AnimeDraft → PeriodicEventDraft（直播/比赛/日程/影视更新），适配器跨领域复用
4. 注意：具体播出时刻多数公开 API 不提供（Bangumi 只给日期+星期），draft.time 留 null 由用户在排期页补

### E2 新增模式（与学校/通用/追剧平级）
1. TimetableConfig 加模式标志字段 + repo save/load 各一行 + settings 模式选择器四选
2. 新建 DSL 生成器纯函数（复用 buildAnimeDsl 结构：时间分组/对齐周一/周期自适应/输出可回灌 DSL）
3. 设置页数据来源区加入口
4. 渲染层不动

### E3 新增 DSL 语法
- 单点改 timetable_dsl_parser.dart + 同步 DSL_FORMAT.md
- 向后兼容：新语法可选、缺省回退（参考 w2-16 范围语法的加法定式：parse + format 对称）

### E4 新增显示配置
- TimetableConfig 字段 + repo 读写 + settings 高级功能区 + `slotLabel()` 路由 + DSL config 段参数
- 存储是 untyped Map，加字段天然向前兼容

## 关键机制（勿破坏）

| 机制 | 位置 | 破坏后果 |
|---|---|---|
| 同 cell 多课程 + visibleInCycles 周期过滤 | cell 渲染/cycleGridProvider | 换课/追剧期数失效 |
| 模式互斥三选 | settings isSchoolMode/isAnimeMode | 模式串扰 |
| 追剧应用顺序：updateConfig → clearAllItems → upsertItems | editor/settings | 越界课程被删/新旧混存 |
| config 段必须在课程行前 | parser 单遍扫描 | slots 约束失效 |
| DSL 回灌闭环（生成→解析一致） | generator + parser | 导入导出失真 |
| default 空间=旧 box 直读 | repo 路由 | 迁移风险/数据丢失 |

## 错误案例

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| 修改渲染层来实现新模式 | 多模式 if-else 蔓延，模块腐化 | 模式=生成器预设，渲染由 config 驱动 |
| 适配器绕过 AnimeDraft 直接造 CourseItem | 丢失缺省字段语义（time 缺失无法提示） | 统一走 AnimeDraft → 排期页补齐 → buildAnimeDsl |
| 大段替换设置页后不 analyze | 括号/缩进错乱编译失败 | 大段编辑后立即 flutter analyze |
| 新 box 忘记注册 StorageRegistry | 存储分析面板看不到 | init() 四件套：guard+adapter+open+register |
| test/ 新增测试不 git add -f | 测试没提交 | test/ 被 .gitignore 忽略，需 -f |
| DSL 只导出课程不带 config 段 | 配置丢失 | exportToDsl 始终携带 config 段 |

## 验证

- `flutter analyze`（基线 197 issues，无新增）
- `flutter test test/core/timetable/anime_dsl_generator_test.dart test/core/timetable/timetable_dsl_config_test.dart`（生成器/w 范围/反推/回灌）
- 改动存储/原生后按 flutter-work-flow 要求验证
