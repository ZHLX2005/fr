---
name: rive-flutter-binding
description: Flutter 项目集成 Rive 0.14.x 动画与 DataBind 数据绑定。触发词：Rive 动画、Rive 数据绑定、ViewModel 绑定、in_input、状态机输入、Rive 面板、Rive Demo。
---

# Rive Flutter 数据绑定 Skill

## 触发场景

- 用户需要在 Flutter 中添加 Rive 动画展示
- 用户需要实现 Flutter 与 Rive 状态机 / ViewModel 的数据双向绑定
- 用户提到 Rive 的 `in_input`、`boolean` 输入、DataBind、ViewModel 等关键词
- 用户要求创建 Rive Lab Demo

## 环境前提

本项目已依赖 `rive: ^0.14.5`，并采用 Rive 0.14.x 的 C++ Runtime API（与 0.13 及之前版本完全不兼容）。

## 核心 API 速查

### 1. 加载 Rive 文件

```dart
import 'package:rive/rive.dart' as rive;

late final rive.FileLoader _fileLoader = rive.FileLoader.fromAsset(
  'assets/rive/your_file.riv',
  riveFactory: rive.Factory.rive, // 或 rive.Factory.flutter
);

@override
void dispose() {
  _fileLoader.dispose();
  super.dispose();
}
```

### 2. 显示 RiveWidget（基础）

```dart
rive.RiveWidgetBuilder(
  fileLoader: _fileLoader,
  builder: (context, state) => switch (state) {
    rive.RiveLoading() => const Center(child: CircularProgressIndicator()),
    rive.RiveFailed() => Text('加载失败: ${state.error}'),
    rive.RiveLoaded() => rive.RiveWidget(
        controller: state.controller,
        fit: rive.Fit.contain,
      ),
  },
)
```

### 3. DataBind — 获取 ViewModelInstance（推荐方式）

**⚠️ 绝不要再用 `state.controller.stateMachine.boolean('xxx')`，该方法已弃用。**

正确做法：

```dart
void _onRiveLoaded(rive.RiveLoaded state) {
  final vmi = state.controller.dataBind(rive.DataBind.auto());
  final boolProp = vmi.boolean('in_input'); // 返回 ViewModelInstanceBoolean?
  boolProp?.value = true;
}
```

### 4. 控制布尔属性

```dart
rive.ViewModelInstanceBoolean? _inInput;

void _setInput(bool value) {
  _inInput?.value = value; // 实时同步到 Rive
}

@override
void dispose() {
  _inInput?.dispose(); // 必须手动 dispose
  _fileLoader.dispose();
  super.dispose();
}
```

## Lab Demo 创建规范

遵循 `flutter-work-flow` skill 的 Demo 规范：

1. **文件位置**：`lib/lab/demos/rive_xxx_demo.dart`（单文件，扁平化）
2. **必须继承 `DemoPage`**：
   ```dart
   class RiveXxxDemo extends DemoPage {
     @override String get title => '标题';
     @override String get description => '描述';
     @override Widget buildPage(BuildContext context) => const _Page();
   }
   ```
3. **注册到 `lib/lab/lab_bootstrap.dart`**：导入并调用 `registerRiveXxxDemo()`
4. **添加资产到 `pubspec.yaml`**：
   ```yaml
   assets:
     - assets/rive/your_folder/
   ```
5. **无返回按钮**：Lab 容器已提供，Demo 内部不要再放 AppBar 返回按钮
6. **运行检查**：
   ```bash
   flutter analyze | grep error
   ```
   无报错后 `git add` 特定文件 → `git commit` → `git push`

## 完整代码模板

```dart
import 'package:flutter/material.dart';
import 'package:rive/rive.dart' as rive;
import '../lab_container.dart';

class RiveDataBindDemo extends DemoPage {
  @override String get title => 'Rive 数据绑定';
  @override String get description => 'Rive ViewModel 布尔属性与 Flutter 映射';
  @override Widget buildPage(BuildContext context) => const _RiveDataBindPage();
}

class _RiveDataBindPage extends StatefulWidget {
  const _RiveDataBindPage();
  @override State<_RiveDataBindPage> createState() => _RiveDataBindPageState();
}

class _RiveDataBindPageState extends State<_RiveDataBindPage> {
  late final rive.FileLoader _fileLoader = rive.FileLoader.fromAsset(
    'assets/rive/input_machine/input_machine.riv',
    riveFactory: rive.Factory.rive,
  );

  rive.ViewModelInstanceBoolean? _inInput;
  bool _inputValue = false;

  @override
  void dispose() {
    _inInput?.dispose();
    _fileLoader.dispose();
    super.dispose();
  }

  void _extractInput(rive.RiveLoaded state) {
    if (_inInput != null) return;
    try {
      final vmi = state.controller.dataBind(rive.DataBind.auto());
      final input = vmi.boolean('in_input');
      if (input != null && mounted) {
        setState(() {
          _inInput = input;
          _inputValue = input.value;
        });
      }
    } catch (_) {}
  }

  void _setInput(bool value) {
    setState(() {
      _inputValue = value;
      _inInput?.value = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          children: [
            Expanded(
              child: rive.RiveWidgetBuilder(
                fileLoader: _fileLoader,
                builder: (context, state) {
                  if (state is rive.RiveLoaded && _inInput == null) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _extractInput(state),
                    );
                  }
                  return switch (state) {
                    rive.RiveLoading() => const CircularProgressIndicator(),
                    rive.RiveFailed() => Text('失败: ${state.error}'),
                    rive.RiveLoaded() => rive.RiveWidget(
                        controller: state.controller,
                        fit: rive.Fit.contain,
                      ),
                  };
                },
              ),
            ),
            Switch(
              value: _inputValue,
              onChanged: _inInput != null ? _setInput : null,
            ),
          ],
        ),
      ),
    );
  }
}

void registerRiveDataBindDemo() {
  demoRegistry.register(RiveDataBindDemo());
}
```

## 错误案例

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| 使用 `state.controller.stateMachine.boolean('in_input')` | IDE 报 deprecated，运行时报弃用警告，未来版本可能移除 | 使用 `state.controller.dataBind(rive.DataBind.auto()).boolean('in_input')` |
| 未 `dispose()` `ViewModelInstanceBoolean` | 原生层内存泄漏 | 在 `dispose()` 中调用 `_inInput?.dispose()` |
| 在 `RiveWidgetBuilder` 的 `builder` 里直接 `setState` 初始化 | 触发 build 阶段 setState 异常 | 使用 `WidgetsBinding.instance.addPostFrameCallback` 延迟初始化 |
| 忘记在 `pubspec.yaml` 注册新的 Rive 资产路径 | 运行时 `FileLoader` 抛异常找不到文件 | 每次新增 .riv 文件都检查并添加 `assets/` 路径 |
| 未在 `lab_bootstrap.dart` 注册 Demo | Lab 列表中看不到新 Demo | 新增 demo 后必须 import 并调用 `registerXxxDemo()` |
| 混用 `rive.Factory.rive` 和 `rive.Factory.flutter` | 渲染行为异常或部分特性不支持 | 根据 Rive 文件设计选择对应 Factory，通常 `Factory.rive` |

## 版本兼容性说明

- **rive ^0.14.0+**：必须使用本 Skill 中的 DataBind / ViewModel API
- **rive ^0.13.x 及更早**：使用旧版 `StateMachineController.findInput<bool>() / SMIBool` API，与本 Skill 不兼容
- 本项目已锁定 `rive: ^0.14.5`，**绝对不要**倒退或混用旧版 API
