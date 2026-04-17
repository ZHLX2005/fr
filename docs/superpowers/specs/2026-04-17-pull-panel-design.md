# 上拉面板 Demo 设计文档

## 概述

实现一个上拉面板组件，功能参考微信小程序：下拉时根据下拉距离显示刷新或展开面板。

## 交互逻辑

| 手势距离 | 阈值 | 行为 |
|----------|------|------|
| 下拉 < 20% | 回弹 | 无操作，松开后回弹 |
| 下拉 20% ~ 50% | 刷新区 | 显示 spinner → 刷新 → 自动收起 |
| 下拉 > 50% | 面板展开区 | 展开面板内容 |

## 状态机

```
IDLE
  └── (下拉超过20%) → REFRESHING → (刷新完成/失败) → IDLE
                     ↘ (下拉超过50%) → PANEL_EXPANDED → (点击收起/下滑) → IDLE
```

## 组件结构

```
PullPanelDemoPage (Scaffold, backgroundColor: #F5EFEA)
└── Stack
    ├── _MainContent
    │   └── 居中图标(Icons.swipe_down) + 文字说明
    │
    ├── Positioned (top: 0)
    │   └── GestureDetector (下拉手势)
    │       └── AnimatedContainer / Transform.translate
    │           └── _PullDownPanel (#122E8A 深海蓝)
    │               ├── 拖拽指示条
    │               ├── 状态提示文字
    │               └── Expanded → ListView (面板内容)
    │
    └── _RefreshOverlay (刷新时遮罩 + spinner)
        └── OverlayEntry → 半透明遮罩 + Center(CircularProgressIndicator)
```

## 颜色定义

| 用途 | 色值 | 说明 |
|------|------|------|
| 主页面背景 | `#F5EFEA` | 柔奶白 |
| 面板背景 | `#122E8A` | 深海蓝 |
| 波浪线 | `Colors.white.withOpacity(0.5)` | 半透明白 |
| 刷新遮罩 | `Colors.black.withOpacity(0.3)` | 半透明黑 |
| spinner | `Colors.white` | 白色 |

## 实现要点

### 1. 下拉手势检测

使用 `GestureDetector` 监听 `onVerticalDragStart/Update/End`：

```dart
GestureDetector(
  onVerticalDragStart: _onDragStart,
  onVerticalDragUpdate: _onDragUpdate,
  onVerticalDragEnd: _onDragEnd,
  child: AnimatedContainer(height: _dragOffset, ...),
)
```

- `_dragOffset` 记录下拉距离
- `pullRatio = _dragOffset / screenHeight` 计算下拉比例

### 2. 阈值判定

状态切换逻辑：
- `pullRatio < 0.2`: 无操作，回弹
- `0.2 <= pullRatio < 0.5`: 刷新区 (REFRESHING)
- `pullRatio >= 0.5`: 面板展开区 (PANEL_EXPANDED)

### 3. 刷新流程

```
用户下拉 → 超过20% → 进入刷新区
        → 松开 → 显示遮罩 + spinner
        → 执行刷新 (模拟3秒延迟)
        → 刷新完成 → 隐藏遮罩 + 收起面板 → IDLE
```

### 4. 动画回弹

使用 `AnimationController` 实现平滑回弹：

```dart
_snapTo(target) {
  _snapController.stop();
  _snapAnimation = _snapController.drive(
    Tween<double>(begin: _dragOffset, end: target),
  );
  _snapController.animateTo(1.0, duration: 300ms);
}
```

## 文件清单

| 文件 | 修改类型 | 说明 |
|------|----------|------|
| `lib/lab/demos/pull_panel_demo.dart` | 重写 | 上拉面板 Demo 页面 |

## 验收标准

1. 主页背景为柔奶白 `#F5EFEA`
2. 面板背景为深海蓝 `#122E8A`
3. 从顶部下拉时面板向下展开
4. 下拉 < 20% 松开后回弹
5. 下拉 20% ~ 50% 显示白色 spinner，3秒后自动收起
6. 下拉 > 50% 展开面板，显示 ListView 内容
7. 刷新时主页面不可交互（遮罩覆盖）
