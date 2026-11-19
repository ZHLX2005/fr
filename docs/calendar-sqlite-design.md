# 日历模块 · SQLite 表与数据访问层设计

> 适用范围：`lib/core/calendar`、`lib/core/storage/sqlite`、`lib/lab/demos/calendar_demo.dart`。
> 目标是把「日历任务」做成可持久化、可迁移、可被其他模块复用的结构化模块，而不是一次性页面。

## 1. 存储选型与边界

- 选用 `sqflite`：走 Android / iOS / macOS 平台自带的 SQLite，不额外打包 `libsqlite3.so`，对 arm64 split APK 的体积增量约为 0.1–0.5 MB。
- 数据库文件：平台默认 databases 目录下的 `xiaodouzi_fr.sqlite`。
- 启用平台：Android / iOS / macOS。Web / Windows / Linux 暂不启用，`sqliteStorageProvider` 为 `null`，日历页显示空状态而不是崩溃。
- 不引入全局单例：数据库生命周期由 `main.dart` 组合根持有，通过 Riverpod Provider 注入。

## 2. 访问分层

```
UI (CalendarPage)
  └─ ref.read(sqliteCalendarRepositoryProvider)
       └─ SqliteCalendarRepository
            └─ SqliteStore（私有 Database，不导出）
                 └─ sqflite Database
```

约束：

1. `SqliteStore` 不对外导出，不提供 `Database` getter；外部只能拿到 Repository。
2. 所有 SQL 只出现在 `lib/core/storage/sqlite/` 内。
3. `test/core/storage/sqlite/sqlite_access_guard_test.dart` 扫描 `lib/`，禁止模块外直接 `import package:sqflite`、引用 `SqliteStore` / `SqliteTransaction` 或调用 `openDatabase`。
4. `SqliteStorage` 是唯一对外入口，暴露 `settings` 与 `calendar` 两个 Repository，自身不暴露低层 Store。

## 3. 表结构（schema v2）

### 3.1 `calendar_tasks`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | INTEGER PK AUTOINCREMENT | 主键 |
| `title` | TEXT NOT NULL | 任务标题，空字符串由 Repository 拒绝 |
| `notes` | TEXT | 备注，可空 |
| `start_at` | INTEGER NOT NULL | 开始时间，本地时间的 epoch ms |
| `end_at` | INTEGER | 结束时间；全天任务通常为次日 00:00；单点任务可为空 |
| `all_day` | INTEGER NOT NULL DEFAULT 0 | 0/1，带 CHECK 约束 |
| `completed_at` | INTEGER | 非空即已完成 |
| `priority` | INTEGER NOT NULL DEFAULT 0 | 0 = 普通，数值越大优先级越高 |
| `color` | INTEGER | ARGB，可空；空时 UI 用主题强调色 |
| `created_at` | INTEGER NOT NULL | 创建时间 |
| `updated_at` | INTEGER NOT NULL | 最近更新时间 |

索引：

```sql
CREATE INDEX idx_calendar_tasks_range ON calendar_tasks (start_at, end_at);
CREATE INDEX idx_calendar_tasks_completed ON calendar_tasks (completed_at);
```

- `idx_calendar_tasks_range` 服务「某天 / 某月范围重叠」查询。
- `idx_calendar_tasks_completed` 服务「隐藏已完成」与后续统计。

### 3.2 `app_settings`

沿用 v1 的键值设置表：

```sql
CREATE TABLE app_settings (
  key TEXT PRIMARY KEY NOT NULL CHECK (length(key) > 0),
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
```

日历偏好写入这里：`calendar.viewMode`、`calendar.showCompleted`、`calendar.mondayFirst`。

## 4. 时间语义

- 所有时间按**本地时间**存 `millisecondsSinceEpoch`，不做 UTC 转换；日历是本地生活工具，跨时区不是当前需求。
- 全天任务：`start_at = 当天 00:00`，`end_at = 次日 00:00`，`all_day = 1`。
- 定时任务：`start_at` 为具体时刻，`end_at` 为结束时刻；结束时刻为次日 00:00 时，不占用次日。
- 范围查询采用半开区间 `[start, end)`：
  - 命中条件：`start_at < 查询结束` 且 `end_at > 查询开始`；
  - `end_at IS NULL` 的任务只落在 `start_at` 当天，不向未来无限延伸；
  - 结束时间恰好为 00:00 的任务，把最后一天回退一天，避免次日重复出现。

## 5. Repository 接口

`SqliteCalendarRepository`：

| 方法 | 用途 |
| --- | --- |
| `tasksOnDay(day, {includeCompleted})` | 某天任务列表；全天优先、未完成优先、按开始时间排序 |
| `taskDateKeysBetween(start, end, {includeCompleted})` | 月网格任务点；返回 `yyyy-mm-dd` 集合，跨天任务展开到每一天 |
| `create(CalendarTaskDraft)` | 新建；标题 trim 后为空抛 `ArgumentError` |
| `update(CalendarTask)` | 覆盖更新一行 |
| `toggleCompleted(CalendarTask)` | 完成/取消完成，写 `completed_at` 与 `updated_at` |
| `delete(int id)` | 删除 |

`SqliteSettingsRepository`：

| 方法 | 用途 |
| --- | --- |
| `read(key)` | 读字符串 |
| `write(key, value)` | 写并更新 `updated_at` |
| `remove(key)` / `readAll()` / `clear()` | 删除 / 全量读 / 清空 |

## 6. 迁移策略

- `SqliteMigrations.version = 2`。
- v1 建 `app_settings`；v2 建 `calendar_tasks` 与两个索引。
- 新增结构时：版本 +1，在 `_migrate` 追加新的 `case`，不修改已发布分支。
- `onCreate` 从 0 逐级执行到当前版本；`onUpgrade` 从旧版本逐级补差。

## 7. 后续扩展点

当前只落一张任务表，刻意不提前引入列表 / 标签 / 提醒：

| 需求 | 建议表 |
| --- | --- |
| 多清单（工作 / 生活 / 学习） | `calendar_lists(id, name, color, sort_order)`，`calendar_tasks.list_id` |
| 标签 | `calendar_tags` + `calendar_task_tags` |
| 提醒 | `calendar_reminders(task_id, trigger_at, repeat_rule)` |
| 重复任务 | `calendar_recurrence_rules(task_id, rrule, until)`，由 Repository 展开实例 |

这些表都通过同一个 `SqliteStore` 访问，不新增第二套数据库入口。

## 8. 验证

- `flutter analyze --no-pub lib/core/calendar lib/core/storage/sqlite lib/lab/demos/calendar_demo.dart lib/main.dart`：无问题。
- `flutter test test/core/storage/sqlite/sqlite_access_guard_test.dart --no-pub`：通过。
- `flutter build web --release --no-pub --no-wasm-dry-run`：通过（Web 端只是不启用 SQLite，不影响编译）。
- 真机验收待做：月/周拖拽、选中日期、添加/完成/删除、设置持久化。
