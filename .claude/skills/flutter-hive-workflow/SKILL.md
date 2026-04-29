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

| 错误 | 原因 | 解决 |
|------|------|------|
| `HiveError: You must provide your type` | 用 `Hive.box(name)` 访问 typed box | 用 `Hive.box<YourModel>(name)` |
| `HiveError: Cannot read from closed box` | box 未打开就访问 | 先检查 `Hive.isBoxOpen()` 或先 `await Hive.openBox()` |
| 删除后数据还在 | key 类型不匹配 | 删除时尝试 string 和 int 两种 key |
| 显示 "Instance of xxx" | `_formatValue()` 未处理自定义类型 | 添加 `if (value is YourModel)` 分支 |

## StorageManager 模式

如果需要管理多种 Hive box，参考 StorageManager 的模式：

```dart
// 硬编码 box 名称列表
final boxNames = [
  'timetable_config',
  'timetable_items',
  'body_records', // typed box 需要特殊处理
  'notes',
];

for (final name in boxNames) {
  if (Hive.isBoxOpen(name)) {
    if (name == 'body_records') {
      final box = Hive.box<BodyRecord>(name); // typed access
      // process...
    } else {
      final box = Hive.box(name);
      // process...
    }
  }
}
```

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
