# 消息策略模式

## 架构

```
IMessageData (接口) → 数据层定义type
       ↓
MessageWidgetStrategy<T> (策略) → 渲染 + createMockData()
       ↓
MessageWidgetFactory (工厂) → O(1)查找
       ↓
GetIt DI注册 → registerMessageStrategies()
```

## 消息类型

| Type | 说明 |
|------|------|
| text | 纯文本消息 |
| markdown | Markdown 格式消息 |
| html | HTML 格式消息 |
| water_capsule | 水胶囊消息 |
| calendar | 日历消息 |
| ask | 问答输入消息 |
| selection | 选项选择消息 |

## 文件结构

```
lib/services/message_strategy/
├── data/                    # 数据类
│   ├── text_message_data.dart
│   ├── markdown_message_data.dart
│   ├── html_message_data.dart
│   ├── water_capsule_message_data.dart
│   ├── calendar_message_data.dart
│   ├── ask_message_data.dart
│   └── selection_message_data.dart
├── interfaces/              # 接口定义
│   ├── message_data.dart
│   └── message_widget_strategy.dart
├── strategies/             # 策略实现
│   └── ...
├── factory/                # 工厂
│   └── message_widget_factory.dart
└── di/                    # DI 注册
    └── message_strategy_di.dart
```

## 添加新消息类型

1. 创建 `data/xxx_message_data.dart` 实现 `IMessageData`
2. 创建 `strategies/xxx_message_strategy.dart` 实现 `MessageWidgetStrategy`
3. 注册到 `data/data.dart` 和 `strategies/strategies.dart`
4. 添加到 `di/message_strategy_di.dart` 的策略列表

## 交互型消息

### Ask 消息

问答输入框，点击确认后锁定内容显示。

### Selection 消息

选项列表，支持单选/多选，点击确认后锁定选项显示。
