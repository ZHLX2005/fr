# Flutter — Reorderable 网格在带阴影容器内拖拽掉帧（RepaintBoundary 隔离）

> 何时读：`flutter_reorderable_grid_view`（或任何逐帧动画网格）放在 modal sheet /
> 卡片等**带 blur 阴影的容器**里，拖拽比别处同款实现卡顿时。

## 现象

同一个 `ReorderableBuilder` + 同一套 `ReorderableAnimationConfig`，在设置页里拖拽
流畅，挪到 ⋯ 溢出弹窗里就掉帧、发闷。参数逐项对比完全一致，怀疑无门。

## 根因

拖拽期间的三类动画——拾起拾取、邻居让位（`draggingPositionChange`，本例 280ms）、
落位飞回（`releasedItem`，本例 360ms）——**每一帧都会把动画区域标脏**，重绘请求沿
render tree 向上传播到最近的 RepaintBoundary：

- 页面侧：`lib/screens/settings/pinned_grid.dart` 里的 `_PinnedGrid` 外包了 `RepaintBoundary`，且整页「明度分层、不用投影」→
  每帧只重绘网格自己那层，代价极小。
- 弹窗侧：网格区没有隔离 → 每帧脏区扩散到整张 sheet 图层，而 sheet 卡片带
  `boxShadow: blurRadius 40` 的大阴影 → **每帧重渲染一次全宽 mask blur**。
  一个 mask blur ≈ 数毫秒 GPU，120Hz 帧预算只有 8.3ms，中端机直接掉帧。

包内机制两处完全一致（`LongPressDraggable` feedback 挂根 Overlay 跟手、
`onReorder` 仅松手经 `_finishDragging` 触发一次、GridView 不挂 key 则
auto-scroll 定时器根本不会创建）——差异全在宿主容器的重绘隔离与阴影。

## 修复

给动画发生的子树包一层 `RepaintBoundary`（main_screen.dart `_openMore` 的
⋯ 网格、`lib/screens/settings/pinned_grid.dart` 的 `_PinnedGrid` 均已加）：

```dart
RepaintBoundary(
  child: Padding(
    padding: ...,
    child: ReorderableBuilder<String>.builder(...),
  ),
),
```

## 判定方法

同参数两处表现不同时，先对比「宿主容器有没有 blur 阴影 + 动画子树有没有
RepaintBoundary」，再怀疑动画参数本身。DevTools repaint 面板可验证：
不隔离时每次换位整张 sheet 闪、隔离后只有网格区闪。

## 次因备忘（手势竞争）

`showModalBottomSheet` 的 `BottomSheet` 会把全部内容包进「下拉关闭」垂直手势
识别器：`longPressDelay` 窗口（200ms）内手指移动超过 touch slop，赢的是 sheet
跟手位移而不是拖拽，拾起失败时整张弹窗会被拖走。页面场景的对手只是外层
ListView 滚动，失败观感轻得多。若真机上「想拖却拖着 sheet 跑」，先查这条；
缓解方向是缩 `longPressDelay` 或对 sheet 关 `enableDrag`（会牺牲下滑关闭手势）。
