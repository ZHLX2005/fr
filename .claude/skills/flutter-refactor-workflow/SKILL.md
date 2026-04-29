---
name: flutter-refactor-workflow
description: Flutter 重构工作流。当用户提到删除页面、移除功能、重构代码、删除引用时使用此技能。执行删除操作后必须立即检查编译错误并修复。
---

# Flutter Refactor Workflow

## 核心原则

删除页面/文件后，**必须立即检查并修复编译错误**，不能只删除文件就提交。

## 工作流程

### 1. 删除文件

```bash
# 删除孤立目录但保留占位文件
rm -rf lib/screens/chat/chat  # 删除chat子目录
```

### 2. 立即检查编译错误

```bash
flutter analyze 2>&1 | grep -E "(error|Error)"
```

### 3. 修复引用错误

删除文件后，常见错误类型：

| 错误类型 | 解决方法 |
|---------|---------|
| `uri_does_not_exist` | 找到引用该文件的 import，删除或修改 import |
| `creation_with_non_type` | 找到使用该类的代码，删除或替换 |
| `undefined_identifier` | 找到使用该标识符的代码，删除或修复 |

**步骤：**
1. 读取报错文件，找到 import 语句
2. 删除 `import '已删除文件.dart'`
3. 找到所有引用已删除类/方法的地方
4. 删除调用代码（通常用空 widget 或移除整个代码块）
5. 如果有 `_openSettings` 等辅助方法被引用，也要删除

### 4. 再次检查

```bash
flutter analyze 2>&1 | grep -E "(error|Error)"
```

确保无错误后再提交。

### 5. 提交推送

```bash
git add <修改的文件路径>
git commit -m "fix: <描述>"
git push
```

## 常见场景

### 删除整个子页面，保留主页
- 删除 `chat/ai_chat_page.dart` 和 `chat/ai_chat_settings_page.dart`
- 修改 `home_page.dart` — 删除 AI Chat 的卡片和 import
- 修改 `agent_chat_page.dart` — 删除对 settings 的引用

### 删除后 home_page 只保留一个卡片
```dart
// 修改前：标题 "AI 助手"，两个卡片
// 修改后：标题改为具体名称，单个卡片
Text('Agent', ...)
Text('事件记录与分析', ...)
```

### 删除 settings 相关代码
需要删除：
- `import 'ai_chat_settings_page.dart'`
- `_openSettings()` 方法
- `SnackBarAction(label: '去设置', onPressed: _openSettings)`
- `IconButton(..., onPressed: _openSettings)`
- `FilledButton.icon(..., onPressed: _openSettings)`

## 关键错误教训

1. **不能只删除文件** — 必须修复所有引用
2. **import 语句可能有多处** — 用 grep 搜索整个项目
3. **辅助方法可能被多处引用** — 先搜索再删除
4. **Flutter analyze 必须通过** — 才能提交
