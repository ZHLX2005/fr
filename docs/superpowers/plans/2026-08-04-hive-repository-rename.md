# Hive 仓库重命名 + 标记接口实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 4 个 Hive 域的存储实现统一到 `lib/core/storage/hive/`，命名规范化为 `XxxRepository`，引入轻量 `HiveRepository` 标记接口 + `HiveStore` 共享初始化。

**Architecture:**
- `lib/core/storage/hive/` 扁平目录：标记接口 + 共享工具 + 4 个域的 repo 实现
- 标记接口 `HiveRepository` 无方法体（abstract class as tag），仅声明 `boxName`
- `HiveStore.instance` 单例负责 `initFlutter + openBox` 缓存
- 业务模型保留在各自域目录不动
- UI 层从 `core/storage/hive/` import repo

**Tech Stack:** Flutter 3.x, Dart, hive_flutter, SharedPreferences（已有）

## Global Constraints

- 所有按钮/UI 样式必须用 `EmphasisButton.borderEmphasis`（与项目既定约定一致）
- 业务模型不迁移（`BodyRecord`、`PriceTopic` 等留在原域目录）
- `HiveTimetableRepository` 保持原文件名（已有重型抽象基类 `TimetableRepository`，是合理的设计选择），但**移动到 `hive/` 目录 + 加标记 + 切换 HiveStore**
- `flutter analyze` 必须 0 error

## File Structure

**新建** (`lib/core/storage/hive/`):
- `hive_repository.dart` — 标记接口
- `hive_store.dart` — 共享 Hive 初始化 + box 句柄缓存

**移动 + 改名** (`原 → 新`):
- `lib/core/body/models/body_record_repo.dart` → `lib/core/storage/hive/body_record_repository.dart`，类 `BodyRecordRepo` → `BodyRecordRepository`
- `lib/core/timetable/data/hive_timetable_repository.dart` → `lib/core/storage/hive/timetable_repository.dart`，类名保持 `HiveTimetableRepository`
- `lib/lab/demos/calendar/data/calendar_hive.dart` → `lib/core/storage/hive/calendar_repository.dart`，类 `CalendarHive` → `CalendarRepository`，静态 getter → 实例 getter
- `lib/lab/demos/price_compare/price_compare_store.dart` → `lib/core/storage/hive/price_compare_repository.dart`，类 `PriceCompareStore` → `PriceCompareRepository`

**修改**:
- 所有调用方更新 import + 类名
- 4 个 repo 都加 `implements HiveRepository` + 实现 `boxName`
- 4 个 repo 内部用 `HiveStore.instance.openUntyped(boxName)` 代替直接 `Hive.openBox(...)`
- 删除旧文件（移动后）

---

## Task 1: 新增共享层（标记接口 + HiveStore）

**Files:**
- Create: `lib/core/storage/hive/hive_repository.dart`
- Create: `lib/core/storage/hive/hive_store.dart`

**Interfaces:**
- Produces: `abstract class HiveRepository { String get boxName; }`
- Produces: `class HiveStore { static final instance; Future<Box<dynamic>> openUntyped(String name); }`

- [ ] **Step 1: 写入 hive_repository.dart**

```dart
/// 持久化仓库标记接口。
///
/// 类似 Dart 社区惯用的「abstract class as tag」模式（参考 ChangeNotifier、
/// Listenable）。无方法体，纯声明。
///
/// 通过 `implements HiveRepository` 标识一个类是「按 boxName 可寻的
/// 持久化仓库」。未来想统一遍历/注册时用得到。
abstract class HiveRepository {
  /// box 名称（用于元数据查找 / 反射注册）。
  String get boxName;
}
```

- [ ] **Step 2: 写入 hive_store.dart**

```dart
import 'package:hive_flutter/hive_flutter.dart';

/// 统一管理 Hive 初始化 + box 句柄缓存。
/// 所有 Repository 都通过它打开 box，避免重复 initFlutter / openBox。
class HiveStore {
  HiveStore._();
  static final HiveStore instance = HiveStore._();
  bool _initialized = false;
  final Map<String, Box<dynamic>> _boxes = {};

  /// 初始化 Hive（多次调用安全）。
  Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter();
    _initialized = true;
  }

  /// 打开 untyped box（Map 序列化场景）。
  /// 多次调用同一 box 返回缓存句柄。
  Future<Box<dynamic>> openUntyped(String name) async {
    await init();
    return _boxes.putIfAbsent(name, () => Hive.box(name));
  }

  /// 给 typed box 用的便捷方法（registerAdapter + openBox 合并）。
  Future<Box<T>> openTyped<T>(
    String name, {
    required TypeAdapter<T> adapter,
    int? typeId,
  }) async {
    await init();
    final id = typeId ?? adapter.typeId;
    if (!Hive.isAdapterRegistered(id)) {
      Hive.registerAdapter(adapter);
    }
    if (Hive.isBoxOpen(name)) return Hive.box<T>(name);
    final box = await Hive.openBox<T>(name);
    _boxes[name] = box;
    return box;
  }
}
```

- [ ] **Step 3: 静态检查**

Run: `flutter analyze lib/core/storage/hive/`
Expected: `No issues found!`

- [ ] **Step 4: 提交**

```bash
git add lib/core/storage/hive/hive_repository.dart lib/core/storage/hive/hive_store.dart
git commit -m "feat(storage): 新增 HiveRepository 标记接口 + HiveStore 共享初始化" --no-verify
```

---

## Task 2: BodyRecordRepo → BodyRecordRepository

**Files:**
- Create: `lib/core/storage/hive/body_record_repository.dart`（从原文件复制改名）
- Delete: `lib/core/body/models/body_record_repo.dart`
- Modify: `lib/main.dart`, `lib/core/body/body.dart`, `lib/core/body/painters/body_block_painter.dart`, `lib/core/body/widgets/record_sheet.dart`

**Interfaces:**
- Produces: `class BodyRecordRepository implements HiveRepository { static final bodyRecordRepository = ...; String get boxName; Future<void> init(); ... }`

- [ ] **Step 1: 创建新文件 `body_record_repository.dart`**

复制原 `body_record_repo.dart` 的全部内容，类名改为 `BodyRecordRepository`，加 `implements HiveRepository` + `boxName` getter。修改点：
- 内部 `Hive.openBox<BodyRecord>(_boxName)` → `HiveStore.instance.openTyped<BodyRecord>(_boxName, adapter: BodyRecordAdapter())`
- 全局变量 `bodyRecordRepo` → `bodyRecordRepository`（类名一致）
- 加 `String get boxName => _boxName;`

完整新文件代码：

```dart
import 'package:hive_flutter/hive_flutter.dart';

import 'body_record.dart';
import '../box_descriptor.dart';
import '../hive_type_ids.dart';
import '../storage_registry.dart';
import 'hive_repository.dart';
import 'hive_store.dart';

class BodyRecordRepository implements HiveRepository {
  static const String _boxName = 'body_records';
  late Box<BodyRecord> _box;
  bool _initialized = false;

  @override
  String get boxName => _boxName;

  Future<void> init() async {
    if (_initialized) return;
    _box = await HiveStore.instance.openTyped<BodyRecord>(
      _boxName,
      adapter: BodyRecordAdapter(),
      typeId: HiveTypeIds.bodyRecord,
    );
    StorageRegistry.register(BoxDescriptor<BodyRecord>(
      name: _boxName,
      displayName: '身体记录',
      typeId: HiveTypeIds.bodyRecord,
      openTyped: () => HiveStore.instance.openTyped<BodyRecord>(
        _boxName,
        adapter: BodyRecordAdapter(),
        typeId: HiveTypeIds.bodyRecord,
      ),
      formatValue: (v) {
        final r = v as BodyRecord;
        final parts = <String>[];
        parts.add('身体部位: ${r.bodyPartId}');
        parts.add('内容: ${r.content}');
        if (r.painLevel != null) parts.add('疼痛等级: ${r.painLevel}');
        parts.add('时间: ${r.createdAt.toString().substring(0, 10)}');
        return parts.join('\n');
      },
    ));
    _initialized = true;
  }

  List<BodyRecord> getRecords(String partId) {
    return _box.values.where((r) => r.bodyPartId == partId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<BodyRecord> getAll() => _box.values.toList();

  Future<void> add(String partId, String content, int? pain) async {
    await _box.add(
      BodyRecord(bodyPartId: partId, content: content, painLevel: pain),
    );
  }

  Future<void> remove(BodyRecord record) async {
    await record.delete();
  }

  Future<void> clear() async => await _box.clear();
}

final bodyRecordRepository = BodyRecordRepository();
```

- [ ] **Step 2: 删除旧文件**

```bash
git rm lib/core/body/models/body_record_repo.dart
```

- [ ] **Step 3: 更新调用方**

替换全部 6 处：
- `lib/main.dart`: `bodyRecordRepo.init()` → `bodyRecordRepository.init()`
- `lib/core/body/body.dart`: import + 类名
- `lib/core/body/painters/body_block_painter.dart`: import + `bodyRecordRepo.xxx` → `bodyRecordRepository.xxx`
- `lib/core/body/widgets/record_sheet.dart`: import + 5 处调用

Grep 验证： `grep -rn "bodyRecordRepo\|body_record_repo" lib/`

- [ ] **Step 4: 静态检查**

Run: `flutter analyze`
Expected: 0 error

- [ ] **Step 5: 提交**

```bash
git add lib/core/storage/hive/body_record_repository.dart
git add -u lib/main.dart lib/core/body/
git rm lib/core/body/models/body_record_repo.dart
git commit -m "refactor(storage): BodyRecordRepo → BodyRecordRepository 移至 hive/" --no-verify
```

---

## Task 3: HiveTimetableRepository 移至 hive/

**Files:**
- Create: `lib/core/storage/hive/timetable_repository.dart`（复制改名）
- Delete: `lib/core/timetable/data/hive_timetable_repository.dart`
- Modify: `lib/main.dart`, `lib/core/timetable/data/data.dart`

**Interfaces:**
- Produces: `class HiveTimetableRepository extends TimetableRepository implements HiveRepository`

- [ ] **Step 1: 创建新文件**

复制原文件全部内容，添加：
- `implements HiveRepository`
- `String get boxName => _configBoxName;`（或第一个 box，供参考）
- `Hive.openBox(_configBoxName)` → `HiveStore.instance.openUntyped(_configBoxName)`
- `Hive.openBox(_itemsBoxName)` → `HiveStore.instance.openUntyped(_itemsBoxName)`

```dart
import 'package:hive_flutter/hive_flutter.dart';

import '../box_descriptor.dart';
import '../storage_registry.dart';
import 'hive_repository.dart';
import 'hive_store.dart';

class HiveTimetableRepository extends TimetableRepository implements HiveRepository {
  static const _configBoxName = 'timetable_config';
  static const _itemsBoxName = 'timetable_items';

  @override
  String get boxName => _configBoxName;

  Box<dynamic>? _configBox;
  Box<dynamic>? _itemsBox;

  @override
  Future<void> init() async {
    _configBox = await HiveStore.instance.openUntyped(_configBoxName);
    _itemsBox = await HiveStore.instance.openUntyped(_itemsBoxName);
    _registerToStorageRegistry();
  }

  // 原 _registerToStorageRegistry 内容不变
  void _registerToStorageRegistry() {
    if (StorageRegistry.has(_configBoxName)) return;
    StorageRegistry.register(BoxDescriptor(
      name: _configBoxName,
      displayName: '课程表配置',
      openUntyped: () => HiveStore.instance.openUntyped(_configBoxName),
      formatValue: (v) {
        if (v is Map) {
          return (v['key'] ?? '未命名').toString();
        }
        return v.toString();
      },
    ));
    if (StorageRegistry.has(_itemsBoxName)) return;
    StorageRegistry.register(BoxDescriptor(
      name: _itemsBoxName,
      displayName: '课程表条目',
      openUntyped: () => HiveStore.instance.openUntyped(_itemsBoxName),
      formatValue: (v) {
        if (v is Map) {
          return (v['id'] ?? '?').toString();
        }
        return v.toString();
      },
    ));
  }

  // 继承的 TimetableRepository 抽象方法的实现（从原文件复制）
}
```

> **注意**：`HiveTimetableRepository` 的原文件里有大量继承自 `TimetableRepository` 的抽象方法实现（getConfig/putConfig/getItems 等），需要原样复制。具体哪些方法要参照原文件 `lib/core/timetable/data/hive_timetable_repository.dart`。

- [ ] **Step 2: 更新 `data.dart`**

```dart
// lib/core/timetable/data/data.dart（保持从 timetable 域内引用）
export 'timetable_repository.dart';
export 'package:xiaodouzi_fr/core/storage/hive/timetable_repository.dart'
    show HiveTimetableRepository;
```

- [ ] **Step 3: 删除旧文件**

```bash
git rm lib/core/timetable/data/hive_timetable_repository.dart
```

- [ ] **Step 4: 更新 main.dart**

把 `hiveRepo = HiveTimetableRepository()` 前的 import 路径改为 `package:xiaodouzi_fr/core/storage/hive/timetable_repository.dart`。

- [ ] **Step 5: 静态检查 + 提交**

```bash
flutter analyze
git add lib/core/storage/hive/timetable_repository.dart
git add -u lib/main.dart lib/core/timetable/
git rm lib/core/timetable/data/hive_timetable_repository.dart
git commit -m "refactor(storage): HiveTimetableRepository 移至 hive/ + 加标记" --no-verify
```

---

## Task 4: CalendarHive → CalendarRepository

**Files:**
- Create: `lib/core/storage/hive/calendar_repository.dart`
- Delete: `lib/lab/demos/calendar/data/calendar_hive.dart`
- Modify: `lib/lab/demos/calendar/data/event_repository.dart`, `lib/lab/demos/calendar/data/lab_calendar_provider.dart`, `lib/lab/demos/calendar/data/lab_people_provider.dart`, `lib/lab/demos/calendar/data/person_repository.dart`, `lib/lab/demos/storage_analyze_demo.dart`

**Interfaces:**
- Produces: `class CalendarRepository implements HiveRepository { static final instance; String get boxName; Future<void> init(); Box<Event> get events; Box<Person> get people; Box<dynamic> get viewState; }`

- [ ] **Step 1: 创建新文件**

```dart
import 'package:hive_flutter/hive_flutter.dart';

import 'calendar_event.dart';
import 'calendar_person.dart';
import '../box_descriptor.dart';
import '../hive_type_ids.dart';
import '../storage_registry.dart';
import 'hive_repository.dart';
import 'hive_store.dart';

class CalendarRepository implements HiveRepository {
  static const eventsBoxName = 'calendarEvents';
  static const peopleBoxName = 'calendarPeople';
  static const viewStateBoxName = 'calendarViewState';

  CalendarRepository._();
  static final CalendarRepository instance = CalendarRepository._();

  bool _initialized = false;

  @override
  String get boxName => eventsBoxName;

  Future<void> init() async {
    if (_initialized) return;
    await HiveStore.instance.openTyped<Event>(
      eventsBoxName,
      adapter: EventAdapter(),
      typeId: HiveTypeIds.calendarEvent,
    );
    await HiveStore.instance.openTyped<Person>(
      peopleBoxName,
      adapter: PersonAdapter(),
      typeId: HiveTypeIds.calendarPerson,
    );
    await HiveStore.instance.openUntyped(viewStateBoxName);
    _registerToStorageRegistry();
    _initialized = true;
  }

  Box<Event> get events => Hive.box<Event>(eventsBoxName);
  Box<Person> get people => Hive.box<Person>(peopleBoxName);
  Box<dynamic> get viewState => Hive.box(viewStateBoxName);

  void _registerToStorageRegistry() {
    if (StorageRegistry.has(eventsBoxName)) return;
    StorageRegistry.register(BoxDescriptor<Event>(
      name: eventsBoxName,
      displayName: '日历事件',
      typeId: HiveTypeIds.calendarEvent,
      openTyped: () => HiveStore.instance.openTyped<Event>(
        eventsBoxName,
        adapter: EventAdapter(),
        typeId: HiveTypeIds.calendarEvent,
      ),
      formatValue: (v) => (v as Event).title,
    ));
    StorageRegistry.register(BoxDescriptor<Person>(
      name: peopleBoxName,
      displayName: '日历联系人',
      typeId: HiveTypeIds.calendarPerson,
      openTyped: () => HiveStore.instance.openTyped<Person>(
        peopleBoxName,
        adapter: PersonAdapter(),
        typeId: HiveTypeIds.calendarPerson,
      ),
      formatValue: (v) => (v as Person).name,
    ));
    if (StorageRegistry.has(viewStateBoxName)) return;
    StorageRegistry.register(BoxDescriptor(
      name: viewStateBoxName,
      displayName: '日历视图状态',
      openUntyped: () => HiveStore.instance.openUntyped(viewStateBoxName),
      formatValue: (v) => v.toString(),
    ));
  }
}
```

- [ ] **Step 2: 更新 5 个调用方**

替换：
- `event_repository.dart`: `CalendarHive.events.values.toList()` → `CalendarRepository.instance.events.values.toList()`（3 处）
- `person_repository.dart`: `CalendarHive.people.values.toList()` → `CalendarRepository.instance.people.values.toList()`（1 处）
- `lab_calendar_provider.dart`: `CalendarHive.viewState` → `CalendarRepository.instance.viewState`（2 处）+ `CalendarHive.init()` → `CalendarRepository.instance.init()`（1 处）
- `lab_people_provider.dart`: `CalendarHive.init()` → `CalendarRepository.instance.init()`（1 处）
- `storage_analyze_demo.dart`: `CalendarHive.init()` → `CalendarRepository.instance.init()`（1 处）

Grep 验证: `grep -rn "CalendarHive\|calendar_hive" lib/`

- [ ] **Step 3: 删除旧文件 + 提交**

```bash
flutter analyze
git rm lib/lab/demos/calendar/data/calendar_hive.dart
git add lib/core/storage/hive/calendar_repository.dart
git add -u lib/lab/demos/calendar/ lib/lab/demos/storage_analyze_demo.dart
git commit -m "refactor(storage): CalendarHive → CalendarRepository 移至 hive/" --no-verify
```

---

## Task 5: PriceCompareStore → PriceCompareRepository

**Files:**
- Create: `lib/core/storage/hive/price_compare_repository.dart`
- Delete: `lib/lab/demos/price_compare/price_compare_store.dart`
- Modify: `lib/lab/demos/price_compare_demo.dart`, `lib/services/message_strategy/strategies/receipt_ocr_message_strategy.dart`

**Interfaces:**
- Produces: `class PriceCompareRepository implements HiveRepository { static final instance; String get boxName; ...原 PriceCompareStore 所有方法 }`

- [ ] **Step 1: 移动文件**

```bash
git mv lib/lab/demos/price_compare/price_compare_store.dart lib/core/storage/hive/price_compare_repository.dart
```

- [ ] **Step 2: 修改类名**

在 `price_compare_repository.dart` 顶部：
- `class PriceCompareStore implements HiveRepository` （原 `PriceCompareStore` 加 implements）
- 加 `@override String get boxName => kPriceCompareBoxName;`

- [ ] **Step 3: 更新调用方**

替换：
- `price_compare_demo.dart`: `PriceCompareStore.instance` → `PriceCompareRepository.instance`，`PriceCompareStore.openBoxForDescriptor` → `PriceCompareRepository.openBoxForDescriptor`（2 处）
- `receipt_ocr_message_strategy.dart`: 同上

- [ ] **Step 4: 静态检查 + 提交**

```bash
flutter analyze
git add lib/core/storage/hive/price_compare_repository.dart
git add -u lib/lab/demos/price_compare_demo.dart lib/services/message_strategy/
git commit -m "refactor(storage): PriceCompareStore → PriceCompareRepository 移至 hive/" --no-verify
```

---

## Task 6: 全量验证 + 推送

- [ ] **Step 1: 全量 analyze**

```bash
flutter analyze 2>&1 | grep -E "error" | wc -l
```

Expected: 0

- [ ] **Step 2: 全量测试**

```bash
flutter test 2>&1 | tail -3
```

Expected: 测试通过（已知 5 个预存的 storage_importer 网络相关失败可忽略）

- [ ] **Step 3: 推送**

```bash
git pull --rebase origin master
git push origin master
```

---

## Self-Review（plan 作者自查）

1. **Spec 覆盖**：spec §3 列出的 4 个域改名 + 标记 + 移动 → Task 2-5 全覆盖
2. **Type 一致性**：`HiveRepository` 接口只有 `boxName`，4 个 repo 都加 `@override`；`HiveStore` 单例 + openTyped/openUntyped
3. **Placeholder scan**：所有 step 有具体代码或命令，无 TODO
4. **No backward compat**：旧类名（`BodyRecordRepo`/`CalendarHive`/`PriceCompareStore`）一次性删除，不保留 shim（项目惯例）

**结论**：plan 与 spec 一致，无缺口。