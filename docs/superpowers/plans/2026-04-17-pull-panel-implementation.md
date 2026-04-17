# 上拉面板 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现上拉面板 Demo，下拉根据距离显示刷新或展开面板

**Architecture:** 使用 `DraggableScrollableSheet` + `NotificationListener` 监听 sheet 位置，判定 20%/50% 阈值触发刷新/展开。海洋波浪使用 `CustomPainter` + `AnimationController` 实现。刷新状态通过 `OverlayEntry` 在主页显示遮罩。

**Tech Stack:** Flutter, DraggableScrollableSheet, CustomPainter, AnimationController, OverlayEntry

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
const _kWaveColor = Colors.white70;
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
  String get description => 'DraggableScrollableSheet上拉展开面板演示';

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

class _PullPanelDemoPageState extends State<PullPanelDemoPage> {
  _PullState _state = _PullState.idle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackgroundColor,
      body: Stack(
        children: [
          _buildMainContent(),
          DraggableScrollableSheet(
            initialChildSize: 0.0,
            minChildSize: 0.0,
            maxChildSize: 0.9,
            snap: true,
            snapSizes: const [0.0, 0.5, 0.9],
            builder: (context, scrollController) {
              return _PullPanel(
                scrollController: scrollController,
                onStateChange: (state) => setState(() => _state = state),
              );
            },
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
          Text('从底部向上拖拽', style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          Text('或点击按钮展开面板', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Commit**

```bash
git add lib/lab/demos/pull_panel_demo.dart
git commit -m "feat(pull_panel): 搭建基础框架，定义颜色和状态枚举"
```

---

## Task 2: 海洋波浪分界线

**Files:**
- Modify: `lib/lab/demos/pull_panel_demo.dart`

- [ ] **Step 1: 创建 _OceanWavePainter**

```dart
class _OceanWavePainter extends CustomPainter {
  final double phase;      // 动画相位 0.0~1.0
  final double amplitude;  // 波浪幅度
  final bool isActive;     // 是否激活动画

  _OceanWavePainter({
    required this.phase,
    required this.amplitude,
    required this.isActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _kWaveColor
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, size.height / 2);

    for (double x = 0; x <= size.width; x += 1) {
      final waveY = isActive
          ? size.height / 2 + amplitude * _sin(x * 0.04 + phase * 2 * 3.14159)
          : size.height / 2;
      path.lineTo(x, waveY);
    }

    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  double _sin(double x) => (x - (x * x * x) / 6 + (x * x * x * x * x) / 120).clamp(-1.0, 1.0);

  @override
  bool shouldRepaint(_OceanWavePainter oldDelegate) =>
      phase != oldDelegate.phase || amplitude != oldDelegate.amplitude || isActive != oldDelegate.isActive;
}
```

- [ ] **Step 2: 创建 _OceanWaveDivider 组件**

```dart
class _OceanWaveDivider extends StatefulWidget {
  final bool isActive;

  const _OceanWaveDivider({required this.isActive});

  @override
  State<_OceanWaveDivider> createState() => _OceanWaveDividerState();
}

class _OceanWaveDividerState extends State<_OceanWaveDivider> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: Size(double.infinity, widget.isActive ? 20 : 8),
          painter: _OceanWavePainter(
            phase: _controller.value,
            amplitude: widget.isActive ? 6.0 : 2.0,
            isActive: widget.isActive,
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/lab/demos/pull_panel_demo.dart
git commit -m "feat(pull_panel): 添加海洋波浪分界线 CustomPainter"
```

---

## Task 3: 阈值判定与状态切换

**Files:**
- Modify: `lib/lab/demos/pull_panel_demo.dart`

- [ ] **Step 1: 在 _PullPanelDemoPageState 添加 NotificationListener**

```dart
// 在 Stack 内 DraggableScrollableSheet 之前添加
NotificationListener<DraggableScrollableNotification>(
  onNotification: (notification) {
    final sheetSize = notification.extent / 0.9; // 转换为实际屏幕占比 0.0~1.0
    // 阈值判定逻辑
    return true;
  },
  child: DraggableScrollableSheet(...),
)
```

- [ ] **Step 2: 实现完整阈值判定逻辑**

```dart
NotificationListener<DraggableScrollableNotification>(
  onNotification: (notification) {
    final sheetSize = notification.extent / 0.9;
    final prevState = _state;

    if (sheetSize < 0.2) {
      _state = _PullState.idle;
    } else if (sheetSize < 0.5) {
      _state = _PullState.refreshing;
    } else {
      _state = _PullState.panelExpanded;
    }

    if (prevState != _state) {
      setState(() {});
    }
    return true;
  },
  child: DraggableScrollableSheet(
    initialChildSize: 0.0,
    minChildSize: 0.0,
    maxChildSize: 0.9,
    snap: true,
    snapSizes: const [0.0, 0.5, 0.9],
    builder: (context, scrollController) {
      return _PullPanel(
        scrollController: scrollController,
        state: _state,
        onStateChange: (state) => setState(() => _state = state),
      );
    },
  ),
)
```

- [ ] **Step 3: Commit**

```bash
git add lib/lab/demos/pull_panel_demo.dart
git commit -m "feat(pull_panel): 添加阈值判定与状态切换逻辑"
```

---

## Task 4: 刷新流程与遮罩

**Files:**
- Modify: `lib/lab/demos/pull_panel_demo.dart`

- [ ] **Step 1: 添加 OverlayEntry 管理方法**

```dart
class _PullPanelDemoPageState extends State<PullPanelDemoPage> {
  _PullState _state = _PullState.idle;
  OverlayEntry? _refreshOverlay;

  @override
  void dispose() {
    _refreshOverlay?.remove();
    super.dispose();
  }

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
    _showRefreshOverlay();
    await Future.delayed(const Duration(seconds: 3)); // 模拟刷新
    _hideRefreshOverlay();
  }
}
```

- [ ] **Step 2: 修改状态判定逻辑，触发刷新**

```dart
if (sheetSize < 0.2) {
  _state = _PullState.idle;
} else if (sheetSize < 0.5) {
  if (_state != _PullState.refreshing) {
    _state = _PullState.refreshing;
    _handleRefresh(); // 触发刷新
  }
} else {
  _state = _PullState.panelExpanded;
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/lab/demos/pull_panel_demo.dart
git commit -m "feat(pull_panel): 添加刷新流程与 Overlay 遮罩"
```

---

## Task 5: _PullPanel 面板组件

**Files:**
- Modify: `lib/lab/demos/pull_panel_demo.dart`

- [ ] **Step 1: 创建 _PullPanel 组件**

```dart
class _PullPanel extends StatelessWidget {
  final ScrollController scrollController;
  final _PullState state;
  final ValueChanged<_PullState> onStateChange;

  const _PullPanel({
    required this.scrollController,
    required this.state,
    required this.onStateChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kPanelColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          _OceanWaveDivider(isActive: state != _PullState.idle),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 30,
              itemBuilder: (context, index) => _buildListItem(index),
            ),
          ),
        ],
      ),
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
        subtitle: Text('这是第 ${index + 1} 项的描述内容', style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
        trailing: const Icon(Icons.chevron_right, color: Colors.white),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/lab/demos/pull_panel_demo.dart
git commit -m "feat(pull_panel): 完成 _PullPanel 面板组件"
```

---

## Task 6: 验收自检

**Files:**
- Modify: `lib/lab/demos/pull_panel_demo.dart`

- [ ] **Step 1: 对照验收标准检查**

验收标准：
1. 主页背景为柔奶白 `#F5EFEA` → `_kBackgroundColor`
2. 面板背景为深海蓝 `#122E8A` → `_kPanelColor`
3. 分界线为海洋波浪效果，下拉时波浪动画激活 → `_OceanWaveDivider`
4. 下拉 < 20% 松开后回弹 → snap + idle 状态
5. 下拉 20% ~ 50% 显示白色 spinner，3秒后自动收起 → `CircularProgressIndicator` + `Future.delayed`
6. 下拉 > 50% 展开面板，显示 ListView 内容 → snapSizes 配置
7. 刷新时主页面不可交互（遮罩覆盖） → `OverlayEntry`

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
| 2 | 面板背景为深海蓝 `#122E8A` | `_kPanelColor` + `Container.color` |
| 3 | 分界线为海洋波浪效果 | `_OceanWavePainter` + `_OceanWaveDivider` |
| 4 | 下拉 < 20% 松开后回弹 | `DraggableScrollableSheet.snap=true` |
| 5 | 下拉 20%~50% 显示 spinner，3秒后收起 | `_showRefreshOverlay()` + `Future.delayed` |
| 6 | 下拉 > 50% 展开面板 | `snapSizes: [0.0, 0.5, 0.9]` |
| 7 | 刷新时主页面不可交互 | `OverlayEntry` 遮罩 |
