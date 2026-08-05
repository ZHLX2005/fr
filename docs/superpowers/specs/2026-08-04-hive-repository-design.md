# Hive 仓库命名与标记接口设计

- **日期**: 2026-08-05
- **作者**: Claude (brainstorming → spec)
- **状态**: 设计中

---

## 1. 背景与目标

### 背景
项目里有 4 个 Hive 持久化域，命名和生命周期模式不统一：

| 当前类名 | 模式 | 问题 |
|---|---|---|
| `BodyRecordRepo` | 全局变量 `bodyRecordRepo`（无后缀） | 不像 Repository；硬单例变量 |
| `HiveTimetableRepository` | 实例 + extends `TimetableRepository` | 有 `Hive` 前缀 |
| `CalendarHive` | 静态方法 | 命名像"工具类"而非"仓库" |
| `PriceCompareStore` | `instance` 单例 | `Store` 后缀暗示"内存状态" |

### 业务目标
1. **命名规范统一**：所有 4 个域都命名为 `XxxRepository`
2. **引入轻量标记接口**：声明"这是一个持久化仓库"，便于类型查找/未来扩展（不强制实现 CRUD 模板）
3. **统一 Hive 初始化入口**：抽 `HiveStore` 单例，所有 Repo 通过它打开 box，避免每个 Repo 各自 `Hive.initFlutter()`
4. **存量代码不破坏**：保持现有方法签名 + 行为，调用方改动最小

### 非目标（YAGNI）
- ❌ 抽 `HiveRepository<T>` 重型抽象基类（带 list/get/put/delete 模板）—— 留给将来
- ❌ 集中到 `lib/core/store/hive/` 目录 —— 保留域自治原则
- ❌ 加 lint 规则禁止 `Hive.openBox` 散落 —— 留给将来
- ❌ 引入 TypeAdapter 工具链 —— `BodyRecord` 等已有 TypeAdapter 不动

---

## 2. 设计

### 2.1 目录结构（你确认的方案）

```
lib/core/storage/
├── box_descriptor.dart            ← 已有
├── storage_registry.dart          ← 已有
├── storage_manager.dart           ← 已有（纯查询代理）
├── storage_exporter.dart          ← 已有
├── storage_importer.dart          ← 已有
├── hive_type_ids.dart             ← 已有（typeId 唯一真相源）
└── hive/                          ← 新增（所有 Hive 仓库实现 + 接口都在这）
    ├── hive_repository.dart       ← 标记接口
    ├── hive_store.dart            ← 共享 Hive 初始化
    ├── body_record_repository.dart
    ├── timetable_repository.dart
    ├── calendar_repository.dart
    └── price_compare_repository.dart
```

**原则**：
- `hive/` 下**扁平**：`hive_repository.dart`（接口）+ `hive_store.dart`（工具）+ 4 个域的 `*_repository.dart`（实现）
- 业务模型（`BodyRecord`、`PriceTopic` 等）仍在各自域目录，不动
- UI 层从 `core/storage/hive/` import repo（如 `package:xiaodouzi_fr/core/storage/hive/body_record_repository.dart`）

---

## 3. 详细改动

### 文件改动一览

**新建**：
- `lib/core/storage/hive/hive_repository.dart`（标记接口）
- `lib/core/storage/hive/hive_store.dart`（共享初始化）

**重命名 + 移动**：
- `lib/core/body/models/body_record_repo.dart` → `lib/core/storage/hive/body_record_repository.dart`，类 `BodyRecordRepo` → `BodyRecordRepository`
- `lib/lab/demos/calendar/data/calendar_hive.dart` → `lib/core/storage/hive/calendar_repository.dart`，类 `CalendarHive` → `CalendarRepository`
- `lib/lab/demos/price_compare/price_compare_store.dart` → `lib/core/storage/hive/price_compare_repository.dart`，类 `PriceCompareStore` → `PriceCompareRepository`

**修改**：
- 所有调用方更新 import + 类名
- `CalendarHive.events/people/viewState` 静态 getter → `calendarRepository.events/people/viewState` 实例 getter
- 4 个类都 `implements HiveRepository` + 实现 `boxName` getter
- 4 个类内部用 `HiveStore.instance.openUntyped(boxName)` 代替直接 `Hive.openBox(...)`

### 调用方更新（grep 结果）

| 旧引用 | 新引用 |
|---|---|
| `bodyRecordRepo` (6 处) | `bodyRecordRepository` |
| `HiveTimetableRepository` (保持) | (不变) |
| `CalendarHive.events/people/viewState/init` (10 处) | `calendarRepository.events/.../init` |
| `PriceCompareStore.instance` (3 处) | `PriceCompareRepository.instance` |

---

## 4. 实施步骤（由 writing-plans 拆解）

1. **新建共享层** `lib/core/storage/hive_repository.dart`（标记接口 + HiveStore）
2. **改名 BodyRecordRepo → BodyRecordRepository** + 标记 + HiveStore 切换
3. **改名 CalendarHive → CalendarRepository** + 静态方法 → 实例 + 标记 + HiveStore 切换
4. **改名 PriceCompareStore → PriceCompareRepository** + 标记 + HiveStore 切换
5. **HiveTimetableRepository 加标记**（不改名）+ 切换 HiveStore
6. **验证**：analyze + 测试 + 推送

---

## 5. 测试 / 验证

- `flutter analyze`：必须 0 error
- 已有的 `body_record_repo_test.dart` / 等测试不破
- 手动验证：Lab → 存储分析 → 4 个 box 仍正常显示

---

## 6. 风险与权衡

| 风险 | 缓解 |
|---|---|
| `CalendarHive` 静态 getter 改了之后，调用方大改 | 一次性 grep 全替换；调用方都是 lab 域内文件 |
| `bodyRecordRepo` 全局变量改名牵涉面广 | 同时改 import + 调用点（grep） |
| `HiveTimetableRepository` 保持命名不一致 | 文档里说明：它有重型抽象基类，是不同的设计选择 |
| 改名后 git log 难追 | commit message 标明每个 rename 的原→新映射 |

---

## 7. 后续（不在本任务）

- 抽 `HiveRepository<T>` 重型 CRUD 基类（4+ 个域时再做）
- 加 lint 规则禁止 `Hive.openBox` 出现在 `core/storage/` 以外
- 集中 box 元数据（typeId、displayName）到 `BoxDescriptor` 自动注册