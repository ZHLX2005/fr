---
name: flutter-add-page-workflow
description: Flutter 添加新页面的工作流。当用户提到创建新页面、新建页面、添加页面时使用此技能。
---

# Flutter Add Page Workflow

## 添加新页面时需要考虑的事项

### 1. 目录结构
- 页面放在 `lib/screens/` 下
- 如果是子模块，创建子目录（如 `lib/screens/chat/chat/`）
- Widget 放在 `lib/widgets/`
- Provider/State 放在 `lib/providers/` 或 `lib/state/`
- Model 放在 `lib/models/`

### 2. 导入路径（重要！）
```
lib/screens/chat/home_page.dart → import 'format_compatibility_page.dart'
lib/screens/chat/chat/format_page.dart → import '../format_compatibility_page.dart' 或 'format_compatibility_page.dart'
lib/screens/chat/chat/xxx.dart → import '../../widgets/xxx.dart'
```

**计算规则：从当前文件位置到目标文件的相对路径**
- `lib/screens/chat/` → `lib/widgets/` = `../../widgets/`
- `lib/screens/chat/chat/` → `lib/widgets/` = `../../../widgets/`

### 3. 避免重复文件
- 创建文件前先 `ls` 检查是否已存在
- 同一目录下不能有两个同名 `.dart` 文件
- 如果要移动文件，先删除旧位置再创建到新位置

### 4. HomePage 卡片导航
- 如果 HomePage 有导航卡片，添加新页面时需要：
  1. 在 HomePage 添加新的 `_ChatTypeCard` 或按钮
  2. Import 新的页面文件（注意路径）
  3. 使用 `Navigator.push` 跳转到新页面

### 5. flutter analyze 检查
- 创建/修改页面后**立即**执行：
  ```bash
  flutter analyze 2>&1 | grep -E "(error|Error)"
  ```
- 常见错误：
  - `uri_does_not_exist` → 导入路径错误
  - `creation_with_non_type` → 类名不存在或 import 缺失
  - `undefined_method` → 方法未定义

### 6. 提交规范
- 不要使用 `git add .`
- 只 add 修改的文件：
  ```bash
  git add lib/screens/chat/home_page.dart lib/screens/chat/chat/new_page.dart
  git commit -m "feat: add new page"
  git push
  ```

### 7. 孤儿文件检查
- 未被引用的文件不会报编译错误
- 使用 `flutter analyze` 检查孤立文件
- 或搜索确认文件是否被引用：
  ```bash
  grep -r "new_page" lib/
  ```

## 错误案例

### 导入路径错误
- 文件在 `lib/screens/chat/chat/` 下
- 错误：`import '../../widgets/xxx.dart'`
- 正确：`import '../../../widgets/xxx.dart'`

### 文件重复
- 已有 `lib/screens/chat/format_compatibility_page.dart`
- 又创建 `lib/screens/chat/chat/format_compatibility_page.dart`
- 导致 import 混乱

### HomePage 路径问题
- 文件在 `lib/screens/chat/chat/`
- HomePage 在 `lib/screens/chat/home_page.dart`
- 错误：`import 'chat/format_compatibility_page.dart'`
- 正确：`import 'format_compatibility_page.dart'`
