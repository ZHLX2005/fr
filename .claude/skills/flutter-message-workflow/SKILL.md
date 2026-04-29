---
name: flutter-message-workflow
description: |
  Flutter消息策略模式工作流程。当需要添加新的消息类型到message_strategy系统时使用此skill。包括：创建IMessageData实现类、创建MessageWidgetStrategy策略类、注册到DI、创建mock数据。确保类型由数据层驱动，策略不重复定义type。
---

# Flutter 消息策略模式工作流程

## 架构概述

```
IMessageData (接口) → 数据层定义type
       ↓
MessageWidgetStrategy<T> (策略) → 渲染 + createMockData()
       ↓
MessageWidgetFactory (工厂) → O(1)查找
       ↓
GetIt DI注册 → registerMessageStrategies()
```

## 添加新消息类型步骤

### 1. 创建 Data 类

位置: `lib/services/message_strategy/data/`

```dart
import '../interfaces/message_data.dart';

class XxxMessageData implements IMessageData {
  final String content; // 业务字段
  XxxMessageData(this.content);
  @override
  String get type => 'xxx'; // type在数据层定义
}
```

### 2. 创建 Strategy 类

位置: `lib/services/message_strategy/strategies/`

```dart
import 'package:flutter/material.dart';
import '../interfaces/interfaces.dart';
import '../data/xxx_message_data.dart';

class XxxMessageWidgetStrategy extends MessageWidgetStrategy<XxxMessageData> {
  @override
  Widget build(BuildContext context, XxxMessageData data) {
    return YourWidget(data: data);
  }

  @override
  XxxMessageData createMockData() => XxxMessageData('mock content');
}
```

### 3. 注册到 exports

- `data/data.dart`: 添加 `export 'xxx_message_data.dart';`
- `strategies/strategies.dart`: 添加 `export 'xxx_message_strategy.dart';`

### 4. 注册到 DI

在 `di/message_strategy_di.dart` 中，添加到策略实例列表：

```dart
final List<MessageWidgetStrategy<IMessageData>> strategyInstances = [
  TextMessageWidgetStrategy(),
  MarkdownMessageWidgetStrategy(),
  HtmlMessageWidgetStrategy(),
  XxxMessageWidgetStrategy(), // 添加新策略
];
```

DI注册循环**不要重复调用createMockData()**：

```dart
final strategies = <String, MessageWidgetStrategy<IMessageData>>{};
final mockData = <String, IMessageData>{};
for (final s in strategyInstances) {
  final mock = s.createMockData();
  strategies[mock.type] = s;
  mockData[mock.type] = mock;
}
```

### 5. 在 main.dart 中调用注册

```dart
import 'services/message_strategy/di/di.dart';

// 在main()中
registerMessageStrategies();
```

## 常见错误

### 1. LateInitializationError: Field has not been initialized

**错误**: 使用 `late final` 但未在 `initState()` 中初始化

**正确**: 在 `initState()` 中初始化
```dart
late final Map<String, IMessageData> _mockData;

@override
void initState() {
  super.initState();
  final factory = GetIt.instance<MessageWidgetFactory>();
  _mockData = {
    for (final type in factory.supportedTypes) type: factory.getMockData(type),
  };
}
```

### 2. GetIt: Object/factory with type is not registered

**错误**: 未调用 `registerMessageStrategies()`

**正确**: 在 `main()` 中调用注册函数
```dart
registerMessageStrategies();
```

### 3. 策略中重复定义type

**错误**: 在Strategy中定义 `String get type => 'xxx';`

**正确**: type由数据层驱动，策略通过 `createMockData().type` 获取
```dart
// 错误 - 不要在策略中定义type
class XxxStrategy extends MessageWidgetStrategy<XxxMessageData> {
  @override
  String get type => 'xxx'; // 不要这样做
}

// 正确 - 策略不定义type，从数据层获取
```

### 4. DI中重复调用createMockData()

**错误**:
```dart
final strategies = <String, MessageWidgetStrategy<IMessageData>>{
  for (final s in strategyInstances) s.createMockData().type: s, // 第一次调用
};
final mockData = <String, IMessageData>{
  for (final s in strategyInstances) s.createMockData().type: s.createMockData(), // 第二次调用
};
```

**正确**: 单次循环复用
```dart
final strategies = <String, MessageWidgetStrategy<IMessageData>>{};
final mockData = <String, IMessageData>{};
for (final s in strategyInstances) {
  final mock = s.createMockData();
  strategies[mock.type] = s;
  mockData[mock.type] = mock;
}
```

### 5. 导入路径错误

**错误**: 从 `lib/services/message_strategy/` 引用 `../../../widgets/` 

**正确**: 确保路径层级正确
```dart
import '../../../widgets/markdown_renderer_widget.dart'; // 从strategies目录出发
import '../data/xxx_message_data.dart'; // 同级目录
```

### 6. withOpacity已废弃

**错误**: `Colors.grey.withOpacity(0.4)`

**正确**: 使用 `withValues(alpha: x)`
```dart
Colors.grey.withValues(alpha: 0.4)
```
