---
name: flutter-message-workflow
description: |
  Flutter消息策略模式工作流程。添加新消息类型到message_strategy系统时使用。包括创建IMessageData、MessageWidgetStrategy、注册DI、创建mock数据。type由数据层定义。交互型消息(输入/选择)需要内部State，使用_StatefulWidget子widget模式。确认后锁定UI状态。
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

**重要**: 交互型消息(输入框、选择列表)需要内部State，使用 `_StatefulWidget子widget` 模式：

```dart
import 'package:flutter/material.dart';
import '../interfaces/interfaces.dart';
import '../data/xxx_message_data.dart';

class XxxMessageWidgetStrategy extends MessageWidgetStrategy<XxxMessageData> {
  @override
  Widget build(BuildContext context, XxxMessageData data) {
    return _XxxContent(data: data);  // 使用内部StatefulWidget
  }

  @override
  XxxMessageData createMockData() => XxxMessageData('mock content');
}

/// 交互内容组件 - 管理内部状态
class _XxxContent extends StatefulWidget {
  final XxxMessageData data;
  const _XxxContent({required this.data});

  @override
  State<_XxxContent> createState() => _XxxContentState();
}

class _XxxContentState extends State<_XxxContent> {
  bool _isFixed = false;  // 锁定状态
  String _fixedValue = '';

  void _handleConfirm() {
    // 更新状态
    setState(() {
      _fixedValue = _getValue();
      _isFixed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 根据 _isFixed 显示不同UI
    if (_isFixed) {
      return _buildFixedContent();
    }
    return _buildInputContent();
  }
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

### 5. 在 main.dart 中调用注册

```dart
import 'services/message_strategy/di/di.dart';

// 在main()中
registerMessageStrategies();
```

## 常见错误

### 1. @override dispose 但方法不存在

**错误**: 在 Strategy 中添加 `dispose` 方法并加 `@override`

**原因**: `MessageWidgetStrategy` 基类没有 `dispose` 方法

**正确**: 不要加 `@override`，直接定义 `void dispose()` 或不加此方法
```dart
// 错误
@override
void dispose() {
  _controller.dispose();
}

// 正确 - 如果确实需要dispose
void dispose() {
  _controller.dispose();
}

// 或者完全不要dispose方法
```

### 2. 策略中重复定义type

**错误**: 在Strategy中定义 `String get type => 'xxx';`

**正确**: type由数据层驱动
```dart
// 错误 - 不要在策略中定义type
class XxxStrategy extends MessageWidgetStrategy<XxxMessageData> {
  @override
  String get type => 'xxx'; // 不要这样做
}

// 正确 - 策略不定义type
```

### 3. withOpacity已废弃

**错误**: `Colors.grey.withOpacity(0.4)`

**正确**: 使用 `withValues(alpha: x)`
```dart
Colors.grey.withValues(alpha: 0.4)
```

### 4. DI中重复调用createMockData()

**错误**:
```dart
final strategies = <String, MessageWidgetStrategy<IMessageData>>{
  for (final s in strategyInstances) s.createMockData().type: s,
};
final mockData = <String, IMessageData>{
  for (final s in strategyInstances) s.createMockData().type: s.createMockData(),
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

### 5. GetIt未注册

**错误**: 未调用 `registerMessageStrategies()`

**正确**: 在 `main()` 中调用
```dart
registerMessageStrategies();
```

## 交互型消息模式 (Ask/Selection)

### Ask 消息模式

问题 + 输入框 + 确认/取消 → 确认后锁定显示

```dart
class _AskContent extends StatefulWidget {
  final AskMessageData data;
  const _AskContent({required this.data});

  @override
  State<_AskContent> createState() => _AskContentState();
}

class _AskContentState extends State<_AskContent> {
  final _controller = TextEditingController();
  bool _isFixed = false;
  String _fixedText = '';

  void _handleConfirm() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        _fixedText = text;
        _isFixed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _isFixed ? _buildFixedContent() : _buildInputArea();
  }
}
```

### Selection 消息模式

问题 + 选项列表 + 确认/取消 → 确认后锁定显示选中项

```dart
class _SelectionContent extends StatefulWidget {
  final SelectionMessageData data;
  const _SelectionContent({required this.data});

  @override
  State<_SelectionContent> createState() => _SelectionContentState();
}

class _SelectionContentState extends State<_SelectionContent> {
  final Set<String> _selectedIds = {};
  bool _isFixed = false;
  Set<String> _fixedIds = {};

  void _handleConfirm() {
    if (_selectedIds.isNotEmpty) {
      setState(() {
        _fixedIds = Set.from(_selectedIds);
        _isFixed = true;
      });
    }
  }

  String _getSelectedLabels() {
    return widget.data.options
        .where((o) => _fixedIds.contains(o.id))
        .map((o) => o.label)
        .join('、');
  }
}
```

## 锁定状态UI样式

确认后显示已锁定内容：

```dart
Widget _buildFixedContent(ThemeData theme) {
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: theme.colorScheme.primary.withValues(alpha: 0.5),
      ),
    ),
    child: Row(
      children: [
        Icon(Icons.check_circle, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(_fixedValue)),
      ],
    ),
  );
}
```
