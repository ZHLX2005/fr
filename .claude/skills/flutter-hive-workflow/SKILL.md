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

→ 完整 6 步流程 + 范本代码已迁移到 ref：[[hive-feature-creation-checklist]]（Step 1–6）。
SKILL 主文档只保留"为什么要走这套约定"的原则说明，避免与 ref 内容重复。

### 一句话原则（不展开）

- typeId 必须是 `HiveTypeIds.xxx` 常量（不要写魔法数字）
- `Hive.openBox<T>(boxName)` 泛型访问（typed box 不能用 `Hive.box(name)`）
- `init()` 四件套：幂等 guard + adapter 注册 + 泛型 open + `StorageRegistry.register(BoxDescriptor)`
- 不要碰 `storage_manager.dart`（它是纯查询代理，所有 box 分支已消除）

## 仓库层统一（≥ 2 个 Hive 域推荐）

→ 详见 [[hive-feature-creation-checklist]] Step 7。
- 所有 Hive 仓库实现搬进 `lib/core/storage/hive/`
- 加 `HiveRepository` 标记接口（`abstract class`，只声明 `boxName`）
- 加 `HiveStore` 单例统一 `initFlutter + box 句柄缓存`
- 命名统一：`XxxRepository`（不再用 `HiveXxx` / `XxxStore` / 静态方法）

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
| [[hive-feature-creation-checklist]] | **新建**带 Hive 存储的模块时：要避免主题/颜色/标签在多个文件散落、要保证 `Lab → 存储分析` 自动显示并可管理；≥ 2 个 Hive 域时也应统一搬到 `core/storage/hive/` 走 `HiveRepository` 标记接口 + `HiveStore` 共享初始化（详见该 ref Step 7） | references/hive-feature-creation-checklist.md |
