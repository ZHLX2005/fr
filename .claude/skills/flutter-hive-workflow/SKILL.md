---
name: flutter-hive-workflow
description: |
  Flutter Hive 存储管理调试和最佳实践。当遇到 Hive 存储相关问题时要使用此 skill：
  - body_records 或其他使用 TypeAdapter 的 HiveObject 无法读写
  - 删除 Hive 数据失败
  - Hive box 类型不匹配错误
  - StorageManager 查看数据显示 "Instance of xxx"
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
| 显示 "Instance of xxx"                     | `_formatValue()` 未处理自定义类型 | 添加`if (value is YourModel)` 分支                     |

## StorageManager 集中面板（BoxDescriptor 注册制）

Lab → 存储分析 中统一观察所有 Hive Box（像 Redis 面板）。**当前架构：** `StorageManager` 不再有 if-else 分支；每个 feature 自己注册 `BoxDescriptor`，面板自动接管展示、格式化、删除、清空。完整原理见 `[[hive-storage-panel]]`。

- **核心组件**：`lib/core/storage/box_descriptor.dart`（自描述结构）+ `storage_registry.dart`（全局注册表）+ `storage_manager.dart`（纯查询代理）
- **feature 只做一件事**：在自己的 `FeatureHive.init()` 或 `Repo.init()` 里调 `StorageRegistry.register(BoxDescriptor<T>(...))`
- **不再动 StorageManager**：所有 typed box 分支已消除；`_readTypedBox` / `_typedBoxNames` / 硬编码 box 列表全部删除
- **注意事项**：typed box 必须用 `Hive.box<T>(name)` 泛型访问；`Hive.box(name)` 会抛 `HiveError`（BoxDescriptor 内部已保证泛型访问）

## 添加一个自定义 Type 的 Hive 存储

**只需 4 步**（完整代码见 `[[hive-storage-panel]]` §3）：

1. 定义数据模型
2. 手写 TypeAdapter（typeId 避开已有：0=BodyRecord, 90=Event, 91=Person）
3. 在 `FeatureHive.init()` 里注册 adapter + 打开 box + **`StorageRegistry.register(BoxDescriptor<T>(...))`**（含 name / displayName / typeId / openTyped / formatValue）
4. Lab → 存储分析 验证

**关键：** 面板不再需要修改。注册即接管。

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
