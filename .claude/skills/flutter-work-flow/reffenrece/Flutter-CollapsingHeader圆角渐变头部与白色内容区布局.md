# Flutter CollapsingHeader 圆角渐变头部与白色内容区布局

## 项目背景

实现一个"主题色头部 + 白色内容区"的 collapsing header 效果：
- 上滑时头部折叠
- 头部底部圆角随拖动从大圆角(60px)渐变为直角
- 标题文字随头部收缩而移动和缩放
- 白色内容区顶部保持大圆角，覆盖在主题色头部下方

## 关键难点

### 1. 圆角交界处视觉效果
- **问题**：白色内容区和主题色头部的交界处要能明显看出圆角效果
- **解决**：整个页面背景设为白色，主题色块只在头部区域，底部大圆角处露出的就是白色背景

### 2. 双重颜色问题
- **问题**：Container 同时设置 `color` 和 `gradient` 会导致两种蓝色叠加
- **解决**：只使用 `gradient`，不使用 `color` 属性

### 3. Pinned 模式的样式冲突
- **问题**：`SliverPersistentHeader` 使用 `pinned: true` 时，Flutter 会对头部应用默认样式处理，导致背景色异常
- **解决**：使用 `pinned: false`，让头部随滚动自然消失

## 核心技术方案

### 架构
```
Scaffold(backgroundColor: Colors.white)
└── CustomScrollView
    └── SliverPersistentHeader(pinned: false)
        └── CollapsingHeaderDelegate
            ├── Positioned(主题色渐变块，底部圆角)
            └── SafeArea(标题内容，居中)
    └── SliverList(白色内容区)
```

### 关键代码模式

```dart
// 圆角随滚动渐变：60px -> 0px
final radius = maxRadius * (1 - t);  // t: 0.0(展开) -> 1.0(折叠)

// 字号随滚动渐变
final fontSize = expandedFontSize - (expandedFontSize - collapsedFontSize) * t;

// 高度随滚动减少
height: expandedHeight - shrinkOffset;

// 注意：Container 只用 gradient，不用 color
Container(
  decoration: BoxDecoration(
    gradient: LinearGradient(...),  // ✓ 正确
    // color: themeColor,            // ✗ 不要同时使用 color
  ),
)
```

### 参数配置

| 参数 | 值 | 说明 |
|------|-----|------|
| expandedHeight | 240.0 | 展开时头部高度 |
| maxRadius | 60.0 | 最大圆角半径 |
| expandedFontSize | 32.0 | 展开时标题字号 |
| collapsedFontSize | 18.0 | 折叠时标题字号 |

## 备选方案对比

| 方案 | 问题 |
|------|------|
| `DraggableScrollableSheet` | 语义不匹配，交互模型不同 |
| `GestureDetector` + `AnimationController` | 代码复杂，需手动管理状态 |
| `SliverAppBar` + `FlexibleSpaceBar` | pinned 模式下背景色处理有问题 |
| `CustomScrollView` + `SliverPersistentHeader(pinned: false)` | ✓ 最终采用 |

## 关键教训

1. **避免同时使用 `color` 和 `gradient`**：会导致颜色叠加，出现双重色调
2. **`pinned: false` 更适合自定义场景**：Flutter 对 pinned 模式的默认处理会干扰自定义样式
3. **圆角效果需要对比**：主题色块底部圆角处露出白色背景，才能体现圆角存在
