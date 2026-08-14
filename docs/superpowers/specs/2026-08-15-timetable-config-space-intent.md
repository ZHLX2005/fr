# 2026-08-15 时间课表配置化 + DSL 增强 + 新番适配 意图文档

> taskget 聚类确认（fr topic: id=24 / 25 / 26，用户已拍板三任务全做）

## 背景与约束

- 用户指定：完成 ui 层、设置页、group(空间) 存储层的相关设置；导入 flutter-work-flow + flutter-hive-workflow 规范
- **存储兼容性**：旧存储（`timetable_config` / `timetable_items` untyped Map box）必须保持可用，新设计不得破坏既有数据
- 参考设计模式：kv 清单头部空间选择（`kvcli_todo_demo.dart` `_openWorkspaceSheet` + 单选 tile + SharedPreferences 持久化激活组）
- Hive 约定：untyped Map box（不引入 TypeAdapter，规避 part 文件 CI 坑）；`HiveStore.openUntyped`；`StorageRegistry.register(BoxDescriptor)`
- test/ 被 .gitignore 忽略，新增测试需 `git add -f`

## 任务 25：显示配置化 + 头部空间选择（核心）

**目标**：把整个课表页面的显示控制配置化，支持通过配置导出/导入完整设置（内容、长度宽度、开始时间、左侧指示），并模仿 kv 清单头部空间选择实现多空间（新番目录/上课课表/日程安排）。

**模型扩展**（TimetableConfig 追加字段，untyped Map 兼容兜底）：
- `leftLabelMode`：左侧指示模式（序号 / 时间段 / 自定义文字）
- `slotLabels`：每节自定义文字列表（与 slotLabelMode 配套）
- `slotStartTimes`：每节开始时间 "HH:mm" 列表
- `slotDurations`：每节时长（分钟）或结束时间；渲染时间段文字用

**存储层（多空间 + 零迁移兼容）**：
- 新 box `timetable_spaces`：key=spaceId → {name, config, items}；`default` 空间 = 旧 box（读旧 box 兜底，不迁移）
- 激活空间 id 存 SharedPreferences（仿 kvcli `kvtodo-default-group`）
- HiveTimetableRepository 扩展：listSpaces / setActiveSpace / loadConfig/loadItems 按激活空间路由
- StorageRegistry 注册新 box

**UI**：
- 头部 AppBar 加空间选择器（icon + 限宽组名 + bottom sheet 单选列表）
- 设置页加"显示控制"区：左侧指示模式/宽度、时间段显示开关、每节时间与自定义文字编辑
- 主页面 `_SlotLabel` 按模式渲染（序号/时间段/自定义文字）

## 任务 26：DSL 增强

**目标**：DSL 表达行数/列数/开始时间的配置。

- parser 支持 config 头部段：`config: days=7 slots=5 cycles=16 start=2026-08-15 mode=general left=时间`
- `DslParseResult` 增加 `config` 字段（可为 null）
- `TimetableStore.exportToDsl()` 导出 config 头部 + 课程行
- 导入对话框支持应用 config 段（预览提示）
- 更新 `lib/core/timetable/DSL_FORMAT.md`

## 任务 24：左侧 cell 自定义文字 + 新番适配器

- 设置页左侧指示自定义文字编辑（cell 文字功能，与任务 25 的 leftLabelMode 合并实现）
- 新番适配器：TimetableAnimeImportDialog，调 bangumi 公开 API（`https://api.bgm.tv/calendar`）拉取按星期分组的新番，勾选导入为课表（daysPerCycle=7，title=动画名，location=更新时刻/平台），实现"追踪动画片的更新时间"

## 验收标准

1. 旧数据（现有 config/items box）打开课表完全不变；新建空间后切换无数据错乱
2. 头部空间选择器可切换空间、激活空间重启后保持
3. 左侧指示支持 序号/时间段/自定义 三模式，设置页可配置并实时生效
4. DSL 导出含 config 头部，导入可还原行列/开始时间
5. 新番导入对话框可拉取列表并导入
6. flutter analyze 无新增 issue；改动 Android 侧不涉及

## 边界

- 不做开始时间滚轮/多实例合并（独立 doubletime demo 属既往边界）
- 不改后端；新番数据走公开 bangumi API
- 旧 box 数据不迁移（读旧 box = default 空间），删除空间只影响新 box
