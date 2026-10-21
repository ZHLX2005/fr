---
name: flutter-debug-logging
description: Use when encountering errors or unexpected behavior in Flutter that needs investigation through strategic logging
---

# Flutter Debug Logging

## Overview

通过 `debugPrint()` 在关键路径添加日志，还原问题现场。AI 主动追踪执行链路，用户热刷新后复现问题。

## When to Use

- Bug 反复出现，根因不明
- UI 状态异常但看不出哪里改变
- 手势/交互行为不符合预期
- 异步操作结果不正确
- 条件分支走入错误路径

## Core Pattern

**核心原则：追踪 Action 链路，日志要连贯可读**

### 1. 按执行顺序记录

```dart
debugPrint('[WidgetA] action: 点击按钮');
debugPrint('[WidgetA] -> 调用 B');
debugPrint('[WidgetB] 收到调用');
debugPrint('[WidgetB] -> 更新状态');
debugPrint('[WidgetB] -> 触发 rebuild');
```

### 2. 关键状态必须记录

```dart
debugPrint('[CardWidget] 当前区域: $currentArea 卡片索引: $index');
debugPrint('[CardWidget] 拖拽偏移: $offset 阈值: $threshold');
```

### 3. 条件分支入口

```dart
debugPrint('[Handler] 条件判断: offset.dx=${dx} > $threshold? ${dx > threshold}');
if (dx > threshold) {
  debugPrint('[Handler] -> 进入右滑分支');
}
```

### 4. 异常捕获点

```dart
catch (e, s) {
  debugPrint('[ApiService] 异常: $e');
  debugPrint('[ApiService] stack: $s');
}
```

## Investigation Flow

```
1. 理解问题描述
2. 定位最可能的执行路径
3. 从入口开始，按执行顺序添加日志
4. 关键状态点必须输出
5. 条件分支判断前打印条件值
6. 用户热刷新复现
7. 根据日志找到断点
8. 修复并验证
```

## Logging Rules

| 规则 | 说明 |
|------|------|
| 带类型标签 | `[ClassName]` 便于过滤 |
| 顺序清晰 | 日志间有因果关系 |
| 状态完整 | 打印所有相关变量 |
| 不过度 | 定位后删除多余日志 |

## Quick Reference

```dart
// 基本
debugPrint('[ClassName] 描述');

// 状态追踪
debugPrint('[ClassName] 变量: $a, $b, $c');

// 条件判断
debugPrint('[ClassName] if判断: x=$x > y=$y = ${x>y}');

// 流程跳转
debugPrint('[ClassName] -> 调用 OtherClass.method()');
```

## Anti-Patterns

| 错误 | 正确 |
|------|------|
| `print('log')` | `debugPrint('[C] log')` |
| `debugPrint('更新')` | `debugPrint('[Widget] 状态更新: $newState')` |
| 满屏日志 | 只在怀疑路径添加 |
| 不带变量 | `debugPrint('[C] x=$x')` |

## Cleanup

问题确认后，删除所有调试日志，保持代码整洁。
