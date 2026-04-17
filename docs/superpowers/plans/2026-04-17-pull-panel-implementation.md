# 上拉面板 Implementation Plan（修正版）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现下拉面板 Demo，下拉根据距离显示刷新或展开面板

**Architecture:** 使用 `GestureDetector` + `AnimationController` 实现下拉手势检测和回弹动画。面板从顶部向下展开，全屏透明手势层确保始终可触摸。

**Tech Stack:** Flutter, GestureDetector, AnimationController, OverlayEntry, Positioned.fill

---

## File Structure

```
lib/lab/demos/pull_panel_demo.dart   # 唯一修改文件
```

---

## Task 1: 基础框架搭建

**Files:**
- Modify: `lib/lab/demos/pull_panel_demo.dart`

- [ ] **Step 1: 定义颜色和状态枚举**

```dart
import 'package:flutter/material.dart';
import '../lab_container.dart';

// 颜色定义
const _kBackgroundColor = Color(0xFFF5EFEA); // 柔奶白
const _kPanelColor = Color(0xFF122E8A);     // 深海蓝
const _kOverlayColor = Colors.black38;

// 状态枚举
enum _PullState { idle, refreshing, panelExpanded }
```

- [ ] **Step 2: 创建 PullPanelDemo 类**

```dart
class PullPanelDemo extends DemoPage {
  @override
  String get title => '上拉面板';

  @override
  String get description => '下拉触发刷新/展开面板演示';

  @override
  Widget buildPage(BuildContext context) {
    return const PullPanelDemoPage();
  }
}
```

- [ ] **Step 3: 创建 PullPanelDemoPage 主页面框架**

```dart
class PullPanelDemoPage extends StatefulWidget {
  const PullPanelDemoPage({super.key});

  @override
  State<PullPanelDemoPage> createState() => _PullPanelDemoPageState();
}

class _PullPanelDemoPageState extends State<PullPanelDemoPage>
    with SingleTickerProviderStateMixin {
  _PullState _state = _PullState.idle;
  OverlayEntry? _refreshOverlay;
  bool _isRefreshing = false;

  // 下拉相关状态
  double _dragOffset = 0.0;
  bool _isDragging = false;
  late AnimationController _snapController;
  late Animation<double> _snapAnimation;

  // 阈值
  static const double _refreshThreshold = 0.2; // 20% 刷新
  static const double _expandThreshold = 0.5; // 50% 展开

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(vsync: this);
    _snapAnimation = _snapController.drive(Tween<double>(begin: 0, end: 0));
  }

  @override
  void dispose() {
    _refreshOverlay?.remove();
    _snapController.dispose();
    super.dispose();
  }
}
```

- [ ] **Step 4: Commit**

```bash
git add lib/lab/demos/pull_panel_demo.dart
git commit -m "feat(pull_panel): 搭建基础框架，定义颜色和状态枚举"
```

---

## Task 2: 手势处理与回弹动画

**Files:**
- Modify: `lib/lab/demos/pull_panel_demo.dart`

- [ ] **Step 1: 添加手势处理方法**

```dart
void _snapTo(double target) {
  _snapController.stop();
  _snapAnimation.removeListener(_onSnapUpdate);

  _snapAnimation = _snapController.drive(
    Tween<double>(begin: _dragOffset, end: target),
  );
  _snapController.value = 0.0;
  _snapAnimation.addListener(_onSnapUpdate);
  _snapController.animateTo(
    1.0,
    duration: const Duration(milliseconds: 300),
    curve: Curves.easeOut,
  );
}

void _onSnapUpdate() {
  setState(() {
    _dragOffset = _snapAnimation.value;
  });
}

void _onDragStart(DragStartDetails details) {
  _isDragging = true;
  _snapController.stop();
}

void _onDragUpdate(DragUpdateDetails details) {
  if (!_isDragging) return;
  setState(() {
    _dragOffset += details.delta.dy;
    _dragOffset = _dragOffset.clamp(0.0, 500.0);
  });

  final screenHeight = MediaQuery.of(context).size.height;
  final pullRatio = screenHeight > 0 ? _dragOffset / screenHeight : 0.0;

  _PullState newState;
  if (pullRatio < _refreshThreshold) {
    newState = _PullState.idle;
  } else if (pullRatio < _expandThreshold) {
    newState = _PullState.refreshing;
  } else {
    newState = _PullState.panelExpanded;
  }

  if (newState != _state) {
    setState(() => _state = newState);
  }
}

void _onDragEnd(DragEndDetails details) {
  _isDragging = false;

  final screenHeight = MediaQuery.of(context).size.height;
  final pullRatio = screenHeight > 0 ? _dragOffset / screenHeight : 0.0;

  if (_state == _PullState.refreshing && !_isRefreshing) {
    _handleRefresh();
  } else if (_state == _PullState.panelExpanded) {
    _snapTo(screenHeight * _expandThreshold);
  } else {
    _snapTo(0.0);
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/lab/demos/pull_panel_demo.dart
git commit -m "feat(pull_panel): 添加手势处理与回弹动画"
```

---

## Task 3: 刷新流程与遮罩

**Files:**
- Modify: `lib/lab/demos/pull_panel_demo.dart`

- [ ] **Step 1: 添加 Overlay 管理方法**

```dart
void _showRefreshOverlay() {
  _refreshOverlay?.remove();
  _refreshOverlay = OverlayEntry(
    builder: (context) => Container(
      color: _kOverlayColor,
      child: const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    ),
  );
  Overlay.of(context).insert(_refreshOverlay!);
}

void _hideRefreshOverlay() {
  _refreshOverlay?.remove();
  _refreshOverlay = null;
}

Future<void> _handleRefresh() async {
  if (_isRefreshing) return;
  _isRefreshing = true;
  _showRefreshOverlay();
  try {
    await Future.delayed(const Duration(seconds: 3));
  } finally {
    _isRefreshing = false;
    _hideRefreshOverlay();
    _snapTo(0.0);
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/lab/demos/pull_panel_demo.dart
git commit -m "feat(pull_panel): 添加刷新流程与 Overlay 遮罩"
```

---

## Task 4: 主页面布局

**Files:**
- Modify: `lib/lab/demos/pull_panel_demo.dart`

- [ ] **Step 1: build 方法和主内容布局**

```dart
@override
Widget build(BuildContext context) {
  final screenHeight = MediaQuery.of(context).size.height;
  final pullRatio = screenHeight > 0 ? _dragOffset / screenHeight : 0.0;

  return Scaffold(
    backgroundColor: _kBackgroundColor,
    body: Stack(
      children: [
        // 主内容
        _buildMainContent(),

        // 下拉面板（从顶部展开）
        if (_dragOffset > 0)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedContainer(
              duration: _isDragging
                  ? Duration.zero
                  : const Duration(milliseconds: 300),
              height: _dragOffset,
              decoration: BoxDecoration(
                color: _kPanelColor,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(20),
                ),
              ),
              child: _PullDownPanel(
                pullRatio: pullRatio,
                state: _state,
              ),
            ),
          ),

        // 全屏透明手势检测层
        Positioned.fill(
          child: GestureDetector(
            onVerticalDragStart: _onDragStart,
            onVerticalDragUpdate: _onDragUpdate,
            onVerticalDragEnd: _onDragEnd,
            behavior: HitTestBehavior.translucent,
            child: const SizedBox.expand(),
          ),
        ),
      ],
    ),
  );
}

Widget _buildMainContent() {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.swipe_down, size: 64, color: Colors.grey.shade400),
        const SizedBox(height: 16),
        Text('下拉触发刷新或展开面板',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
        const SizedBox(height: 8),
        Text('下拉 < 20% 回弹',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
        Text('下拉 20% ~ 50% 刷新',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
        Text('下拉 > 50% 展开面板',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
      ],
    ),
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/lab/demos/pull_panel_demo.dart
git commit -m "feat(pull_panel): 完成主页面布局与手势层"
```

---

## Task 5: _PullDownPanel 面板组件

**Files:**
- Modify: `lib/lab/demos/pull_panel_demo.dart`

- [ ] **Step 1: 创建 _PullDownPanel 组件**

```dart
class _PullDownPanel extends StatelessWidget {
  final double pullRatio;
  final _PullState state;

  const _PullDownPanel({
    required this.pullRatio,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 拖拽指示器
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        // 状态提示
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            state == _PullState.refreshing ? '正在刷新...' : '下拉展开面板',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 14,
            ),
          ),
        ),
        // 面板内容
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 30,
            itemBuilder: (context, index) => _buildListItem(index),
          ),
        ),
      ],
    );
  }

  Widget _buildListItem(int index) {
    return Card(
      color: Colors.white.withValues(alpha: 0.1),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.white.withValues(alpha: 0.2),
          child: Text('${index + 1}', style: const TextStyle(color: Colors.white)),
        ),
        title: Text('列表项 ${index + 1}', style: const TextStyle(color: Colors.white)),
        subtitle: Text('这是第 ${index + 1} 项的描述内容',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
        trailing: const Icon(Icons.chevron_right, color: Colors.white),
      ),
    );
  }
}
```

- [ ] **Step 2: 添加 registerPullPanelDemo 函数**

```dart
void registerPullPanelDemo() {
  demoRegistry.register(PullPanelDemo());
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/lab/demos/pull_panel_demo.dart
git commit -m "feat(pull_panel): 完成 _PullDownPanel 面板组件"
```

---

## Task 6: 验收自检

**Files:**
- Modify: `lib/lab/demos/pull_panel_demo.dart`

- [ ] **Step 1: 对照验收标准检查**

验收标准：
1. 主页背景为柔奶白 `#F5EFEA` → `_kBackgroundColor`
2. 面板背景为深海蓝 `#122E8A` → `_kPanelColor`
3. 从顶部下拉时面板向下展开
4. 下拉 < 20% 松开后回弹
5. 下拉 20% ~ 50% 显示白色 spinner，3秒后自动收起
6. 下拉 > 50% 展开面板，显示 ListView 内容
7. 刷新时主页面不可交互（遮罩覆盖）

- [ ] **Step 2: 运行测试**

```bash
flutter run -d <device> lib/lab/demos/pull_panel_demo.dart
```

手动验证交互流程。

- [ ] **Step 3: 最终 Commit**

```bash
git add lib/lab/demos/pull_panel_demo.dart
git commit -m "feat(pull_panel): 完成上拉面板功能"
```

---

## 验收标准检查清单

| # | 标准 | 实现位置 |
|---|------|----------|
| 1 | 主页背景为柔奶白 `#F5EFEA` | `_kBackgroundColor` + `Scaffold.backgroundColor` |
| 2 | 面板背景为深海蓝 `#122E8A` | `_kPanelColor` + Container.color |
| 3 | 从顶部下拉时面板向下展开 | `Positioned` + `AnimatedContainer` |
| 4 | 下拉 < 20% 松开后回弹 | `_snapTo(0.0)` |
| 5 | 下拉 20%~50% 显示 spinner，3秒后收起 | `_showRefreshOverlay()` + `Future.delayed` |
| 6 | 下拉 > 50% 展开面板 | `_snapTo(screenHeight * _expandThreshold)` |
| 7 | 刷新时主页面不可交互 | `OverlayEntry` 遮罩 |
