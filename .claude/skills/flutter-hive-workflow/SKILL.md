---
name: flutter-hive-workflow
description: |
  Flutter Hive 存储管理调试和最佳实践。当遇到 Hive 存储相关问题时要使用此 skill：
  - body_records 或其他使用 TypeAdapter 的对象无法读写
  - 删除 Hive 数据失败（key 类型不匹配：string/int）
  - Hive box 类型不匹配错误（"You must provide your type"）
  - 存储面板 (`Lab → 存储分析`) 看不到新建的 box，或显示 "Instance of xxx"
  - 任何 Hive box 打开/访问问题
---
# Flutter Hive Storage Workflow

## 核心原则

**访问 typed box 必须用泛型**：`Hive.box<YourModel>(name)` 而不是 `Hive.box(name)`

## 调试步骤

### 1. 检查 Box 是否已打开

```dart
if (Hive.isBoxOpen(name)) {
  // 已打开，直接访问
} else {
  // 未打开，需要先打开
}
```

### 2. 访问 typed box（使用 TypeAdapter 的 Model）

```dart
// 正确方式
final box = Hive.box<YourModel>(name);

// 错误方式会报错
final box = Hive.box(name); // HiveError: You must provide your type as adapter
```

### 3. 注册 Adapter（如果需要）

```dart
// 在打开 typed box 之前注册
if (!Hive.isAdapterRegistered(0)) { // typeId = 0
  Hive.registerAdapter(YourModelAdapter());
}
final box = await Hive.openBox<YourModel>(name);
```

### 4. 删除操作 - 处理 Key 类型问题

Hive key 有类型存储（int/string）。删除时两种都尝试：

```dart
Future<bool> delete(String boxName, String key) async {
  final box = Hive.box<YourModel>(boxName);
  
  // 尝试 string key
  if (box.containsKey(key)) {
    await box.delete(key);
    return true;
  }
  
  // 尝试 int key（如果存储时用 int 作为 key）
  final intKey = int.tryParse(key);
  if (intKey != null && box.containsKey(intKey)) {
    await box.delete(intKey);
    return true;
  }
  
  return false;
}
```

### 5. 格式化自定义对象显示

`_formatValue()` 需要对自定义类型做特殊处理：

```dart
String _formatValue(dynamic value) {
  if (value is YourModel) {
    return '字段1: ${value.field1}\n字段2: ${value.field2}';
  }
  // Map/List 等其他类型...
}
```

## 常见错误

| 错误                                       | 原因                                | 解决                                                     |
| ------------------------------------------ | ----------------------------------- | -------------------------------------------------------- |
| `HiveError: You must provide your type`  | 用`Hive.box(name)` 访问 typed box | 用`Hive.box<YourModel>(name)`                          |
| `HiveError: Cannot read from closed box` | box 未打开就访问                    | 先检查`Hive.isBoxOpen()` 或先 `await Hive.openBox()` |
| 删除后数据还在                             | key 类型不匹配                      | 删除时尝试 string 和 int 两种 key                        |
| 显示 "Instance of xxx"                     | 面板用了 `Hive.box(name)` 读 typed 对象 | 注册 `BoxDescriptor.formatValue` 告诉面板如何格式化；并改用 `Hive.box<T>(name)` 泛型访问 |

## StorageManager 集中面板（BoxDescriptor 注册制）

Lab → 存储分析 中统一观察所有 Hive Box（像 Redis 面板）。**当前架构：** `StorageManager` 不再有 if-else 分支；每个 feature 自己注册 `BoxDescriptor`，面板自动接管展示、格式化、删除、清空。完整原理见 `[[hive-storage-panel]]`。

- **核心组件**：`lib/core/storage/box_descriptor.dart`（自描述结构）+ `lib/core/storage/storage_registry.dart`（全局注册表）+ `lib/core/storage/storage_manager.dart`（纯查询代理）
- **feature 只做一件事**：在自己的 `FeatureHive.init()` 或 `Repo.init()` 里调 `StorageRegistry.register(BoxDescriptor<T>(...))`
- **不再动 StorageManager**：所有 typed box 分支已消除；`_readTypedBox` / `_typedBoxNames` / 硬编码 box 列表全部删除
- **注意事项**：typed box 必须用 `Hive.box<T>(name)` 泛型访问；`Hive.box(name)` 会抛 `HiveError`（BoxDescriptor 内部已保证泛型访问）

## 添加一个自定义 Type 的 Hive 存储

**完整 6 步流程**（范本：`lib/core/body/models/body_record_repo.dart`）：

### Step 1：在 `lib/core/storage/hive_type_ids.dart` 分配 typeId

**这是 typeId 的唯一真相源**。`HiveTypeIds` 是 `abstract final class`，所有 typed model 的 `typeId` 必须从这里取（不要在别处写魔法数字）：

```dart
// lib/core/storage/hive_type_ids.dart 内追加（core 区段 0-9 / lab 80-99）
static const int myFeature = 92;  // 选一个未占用的
```

参考值（2026-08 当前已分配）：`0=bodyRecord, 90=calendarEvent, 91=calendarPerson`。

### Step 2：定义数据模型

```dart
@HiveType(typeId: HiveTypeIds.myFeature)  // 用常量，不用魔法数字
class MyItem {
  @HiveField(0) final String id;
  @HiveField(1) final String content;
  // ...
}
```

或手写 `MyItemAdapter extends TypeAdapter<MyItem>`（如果项目不用 `hive_generator`）。

### Step 3：创建 `your_feature_repo.dart`，init() 里四件套

**关键**：init() 里有 4 个标准动作（参考 `body_record_repo.dart`）：

```dart
Future<void> init() async {
  if (_initialized) return;                           // 1) 幂等 guard（防重复 init）
  await Hive.initFlutter();
  if (!Hive.isAdapterRegistered(HiveTypeIds.myFeature)) {  // 2) adapter 注册要 guard
    Hive.registerAdapter(MyItemAdapter());
  }
  _box = await Hive.openBox<MyItem>(_boxName);       // 3) 泛型 open（不是 Hive.openBox）
  StorageRegistry.register(BoxDescriptor<MyItem>(  // 4) 注册到面板（漏了面板看不到）
    name: _boxName,
    displayName: '我的功能',
    typeId: HiveTypeIds.myFeature,
    openTyped: () => Hive.openBox<MyItem>(_boxName),
    formatValue: (v) => '内容: ${(v as MyItem).content}',
  );
  _initialized = true;
}
```

### Step 4：在 main.dart 启动期调一次

```dart
await myFeatureRepo.init();
```

**对延迟 init 的 feature**（如 calendar），在自己的 `xxxHive.init()` 里做（参考 `lib/lab/demos/calendar/data/calendar_hive.dart`）—— `StorageManager` 在 Lab 存储分析页 `_ensureBoxesInitialized()` 兜底重试。

### Step 5：不要动 `StorageManager` 任何一行

`storage_manager.dart` 是纯查询代理，**没有 typed box 分支**（`_readTypedBox` / `_typedBoxNames` 已删）。新增 box 一律走 `StorageRegistry.register(BoxDescriptor)` 接入。

### Step 6：验证

```bash
flutter analyze  # 必须 0 error
```

Lab → 存储分析 → 你的 box 自动出现（"我的功能" + keys 列表 + 删除/清空按钮）。

**关键：** 面板不再需要修改。**注册即接管**。

## 调试技巧

使用 `debugPrint` 添加日志：

```dart
debugPrint('StorageManager: 尝试处理 box: $name');
if (Hive.isBoxOpen(name)) {
  debugPrint('StorageManager: $name 已打开');
  final box = Hive.box<BodyRecord>(name);
  debugPrint('StorageManager: $name 长度=${box.length}');
  for (final key in box.keys) {
    debugPrint('StorageManager: 获取键 $key, value类型=${box.get(key).runtimeType}');
  }
}
```

## 引用索引

| ref | 何时读取 | 路径 |
|-----|---------|------|
| [[hive-storage-panel]] | 需要设计新 feature 的 Hive 存储结构、手写 TypeAdapter、或新增 box 到 StorageManager 面板时 | references/hive-storage-panel.md |
| [[hive-feature-creation-checklist]] | **新建**带 Hive 存储的模块时：要避免主题/颜色/标签在多个文件散落、要保证 `Lab → 存储分析` 自动显示并可管理 | references/hive-feature-creation-checklist.md |
