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
    │   └── 居中图标(Icons.swipe_down) + 文字 + 打开面板按钮
    │
    ├── DraggableScrollableSheet
    │   ├── initialChildSize: 0.0
    │   ├── minChildSize: 0.0
    │   ├── maxChildSize: 0.9
    │   ├── snap: true
    │   ├── snapSizes: [0.0, 0.5, 0.9]  ← 0.5 = 50%阈值, 0.9 = 最大展开
    │   └── builder → _PullPanel
    │       └── Container (#122E8A 深海蓝)
    │           ├── _OceanWaveDivider (拖拽指示条 + 波浪动画)
    │           └── Expanded → ListView (面板内容)
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

### 1. 阈值判定

使用 `NotificationListener<DraggableScrollableNotification>` 监听 sheet 位置：

```dart
// 0.0 ~ 1.0 代表屏幕高度比例
// 20% 刷新阈值 → sheet 显示 20% 时触发刷新
// 50% 面板阈值 → sheet 显示 50% 时进入面板展开模式
```

状态切换逻辑：
- `sheetSize < 0.2`: 无操作
- `0.2 <= sheetSize < 0.5`: 刷新区 (REFRESHING)
- `sheetSize >= 0.5`: 面板展开区 (PANEL_EXPANDED)

### 2. 海洋波浪分界线

```dart
class _OceanWaveDivider extends StatefulWidget {
  final bool isActive;  // 下拉时激活波浪动画
}

class _OceanWavePainter extends CustomPainter {
  // 贝塞尔曲线绘制波浪
  // phase 用于动画偏移
}
```

- 静止时：轻微波浪或静态线条
- 拉动时：波浪幅度增大 + 动画
- 刷新时：大波浪动画
- 收起后：波浪逐渐平息

### 3. 刷新流程

```
用户下拉 → 超过20% → 显示遮罩 + spinner
        → 进入刷新区 → 执行刷新 (模拟3秒延迟)
        → 刷新完成 → 隐藏遮罩 + 收起面板 → IDLE
```

### 4. DraggableScrollableSheet 配置

```dart
DraggableScrollableSheet(
  initialChildSize: 0.0,
  minChildSize: 0.0,
  maxChildSize: 0.9,
  snap: true,
  snapSizes: const [0.0, 0.5, 0.9],
  builder: (context, scrollController) => _PullPanel(...),
)
```

注意：`DraggableScrollableSheet` 的 `sheetSize` 是相对于 `maxChildSize` 的比例，需要转换计算实际屏幕占比。

## 文件清单

| 文件 | 修改类型 | 说明 |
|------|----------|------|
| `lib/lab/demos/pull_panel_demo.dart` | 重写 | 上拉面板 Demo 页面 |

## 验收标准

1. 主页背景为柔奶白 `#F5EFEA`
2. 面板背景为深海蓝 `#122E8A`
3. 分界线为海洋波浪效果，下拉时波浪动画激活
4. 下拉 < 20% 松开后回弹
5. 下拉 20% ~ 50% 显示白色 spinner，3秒后自动收起
6. 下拉 > 50% 展开面板，显示 ListView 内容
7. 刷新时主页面不可交互（遮罩覆盖）
