---
name: floating-pill-bottom-nav
description: Bottom Bar 样式 · 子类方案 —— 固定宽胶囊形 Card 容器 + 圆角胶囊指示器在 N-Tab 间用自定义 QQ 弹跳曲线（指数衰减余弦）滑动。
---

# Floating Pill Bottom Navigation

> 分类：样式大类 = **Bottom Bars**，子类 = **Floating Pill Bottom Nav（胶囊滑动指示器底部导航）**。

视觉目标：底部一个 328×64、整体圆角 32 的胶囊形卡片容器，均分 N 个 Tab 项；选中项背后 90×50、圆角 25、primary@20% 透明度的小胶囊会在切换时用自定义 QQ 弹跳曲线从上一个 Tab 滑到下一个图标下方。落地代码：`lib/widgets/xiaodouzi_bottom_bar.dart`。

---

## 一、实现思路

### Step 1 · 状态：prev / currentIndex / AnimationController

```dart
class _State extends State<XiaoDouZiBottomBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final CurvedAnimation _curve;
  int _prev = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(duration: const Duration(milliseconds: 300), vsync: this);
    _curve = CurvedAnimation(parent: _ctrl, curve: const _QQCurve());
  }

  @override
  void didUpdateWidget(XiaoDouZiBottomBar old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      _prev = old.currentIndex;       // 记录起点
      _ctrl.forward(from: 0);          // 重启动画
    }
  }

  @override
  void dispose() { _curve.dispose(); _ctrl.dispose(); super.dispose(); }
}
```

`didUpdateWidget` 监听 currentIndex 变化并驱动动画；`_prev` 静态保持 prev 值，动画进行中不变。

### Step 2 · QQ 曲线（指数衰减余弦）

```dart
import 'dart:math' show exp, cos;

class _QQCurve extends Curve {
  const _QQCurve();
  @override
  double transform(double t) => 1 - exp(-4.5 * t) * cos(9.425 * t);
}
```

- `Curves.linear` / `easeOutCubic`：胶囊机械滑动 / 减速但不弹
- `Curves.elasticOut`：弹过头（多次过冲）
- `_QQCurve`：指数衰减包络 + 单次过冲 → "Q 弹"视觉
- 经验公式 `1 - exp(-k·t)·cos(ω·t)`，本方案 `k=4.5 / ω=9.425` 是肉眼调好的"够弹不过头"

### Step 3 · 几何参数与 capsuleLeft

```dart
static const double _barWidth = 328;
static const double _barHeight = 64;
static const double _capsuleW = 90;
static const double _capsuleH = 50;

final itemW = _barWidth / _icons.length;

double capsuleLeft(int idx) => idx * itemW + (itemW - _capsuleW) / 2;
```

- `_barWidth` 固定 328（撑满屏即失去悬浮感）
- 胶囊竖直居中：`(_barHeight - _capsuleH) / 2`

### Step 4 · 三层 Stack（顺序关键）

```dart
SizedBox(
  height: _barHeight + bottomInset + 20,            // bottomInset 避 home indicator
  child: Align(
    alignment: Alignment.topCenter,
    child: SizedBox(width: _barWidth, height: _barHeight,
      child: Stack(children: [
        // (1) 背景 Card —— 圆角胶囊形
        Card(elevation: 2, margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_barHeight / 2)),
          child: SizedBox(width: _barWidth, height: _barHeight)),
        // (2) 滑动胶囊指示器（AnimatedBuilder + Padding + Container）
        AnimatedBuilder(animation: _curve, builder: (_, __) {
          final t = _curve.value;
          final left = (capsuleLeft(_prev) + (capsuleLeft(widget.currentIndex) - capsuleLeft(_prev)) * t)
                       .clamp(0.0, _barWidth - _capsuleW);
          return Padding(padding: EdgeInsets.fromLTRB(left, (_barHeight - _capsuleH) / 2, 0, 0),
            child: Container(width: _capsuleW, height: _capsuleH,
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(_capsuleH / 2))));
        }),
        // (3) Tab 图标（Row + Expanded + GestureDetector + Icon）
        Positioned.fill(child: Row(children: List.generate(_icons.length, (i) {
          final isActive = widget.currentIndex == i;
          return Expanded(child: GestureDetector(
            onTap: () => widget.onItemSelected(i),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(height: _barHeight, child: Center(child: Icon(
              isActive ? _activeIcons[i] : _icons[i],
              size: 22,
              color: isActive ? primaryColor : inactiveColor,
            )))));
        }))),
      ]),
    ),
  ),
);
```

**栈序**：Card → AnimatedBuilder(capsule) → Positioned.fill(icons)。胶囊在背景之上、图标之下，让图标 primary 实色浮在胶囊 primary@20% 半透明上 → 既有深度又有 identity。

### Step 5 · 颜色

```dart
final primaryColor = cs.primary;
final inactiveColor = primaryColor.withValues(alpha: 0.4);
```

- 选中：图标 = primary，胶囊 = primary@20%
- 未选中：图标 = primary@40%
- **只用 primary 一种色**（不同 alpha 衍生），不要 onSurface 派生

### Step 6 · 验收

- [ ] 初始 currentIndex=0：胶囊停第一个 Tab 中心
- [ ] 切换：胶囊弹跳滑到新 Tab（旧图标回灰、新图标变 primary）
- [ ] bottomInset + 20 防止 home indicator 遮挡
- [ ] 重复点同 Tab：didUpdateWidget 检测相等、不重启动画
- [ ] dispose 释放 _ctrl / _curve
- [ ] 主题切换：胶囊与图标颜色随 cs.primary 联动

---

## 二、踩坑总结

> 本节为本方案实操踩过的真坑。"现象 → 根因 → 结论"格式。

### 坑 1 · `width: double.infinity` 撑满 → 失去悬浮感

撑满屏就回到 Material 默认 bottom bar 风格。**结论**：固定 `_barWidth = 328`（匹配 ~90% 屏宽），不要响应式撑满。

### 坑 2 · 胶囊位置与 Tab 中心错位

`capsuleLeft(idx) = idx * itemW + (itemW - _capsuleW) / 2` 依赖 `_barWidth / N` 整数等分。**结论**：`itemW = _barWidth / N` 强制等分，容器 width 用 SizedBox(width: _barWidth) 锁死，禁止 LayoutBuilder 取实际宽度（引入舍入误差）。

### 坑 3 · Active 图标被胶囊"压在身后"

Stack 顺序写反（胶囊在图标之上）→ 选中图标完全被胶囊色块覆盖。**结论**：固定 `Card → AnimatedBuilder(capsule) → Positioned.fill(icons)`。

### 坑 4 · didUpdateWidget 里写 `setState`

不需要。`setState` 触发 widget 树重建是无意义成本，动画靠 `_ctrl.forward()` 驱动。**结论**：didUpdateWidget 只负责记录 `_prev` + 重启动画，**不要**写 `setState(() {})`。

### 坑 5 · 用 `Curves.elasticOut` 替代 QQ → 抖动过头

elasticOut 内置多次过冲，胶囊来回抖几次。**结论**：`_QQCurve` 单次过冲刚好；嫌弹可换 `Curves.easeOutCubic` / `Curves.easeOutBack`；注意 elasticOut 的过冲系数可能让 t 越过 [0,1]，需手动 `t.clamp`。

### 坑 6 · primary 实色给图标 + 胶囊同时 → 视觉扁平

primary + primary 都是实色 → 单色 plane 无 depth。**结论**：胶囊 = primary@20%、图标 = primary 实色，active 视觉靠"图标实色 + 胶囊浅色"两层叠出。

### 坑 7 · 给胶囊加 elevation / shadow

加 shadow 后 Container 的 `borderRadius + color` 不再自动 ClipRRect，会出现方角。**结论**：当前无阴影，borderRadius 直接生效；如未来加阴影必须显式包 `ClipRRect(borderRadius: ...)`。

---

## 关键参数一览

| 参数 | 值 | 备注 |
|---|---|---|
| `_barWidth` | 328 | 悬浮固定宽，不撑满 |
| `_barHeight` | 64 | |
| `_capsuleW` | 90 | |
| `_capsuleH` | 50 | |
| Bar 圆角 | `_barHeight / 2` (32) | 完全胶囊 |
| 胶囊圆角 | `_capsuleH / 2` (25) | 完全胶囊 |
| 动画时长 | 300 ms | 配 QQ 曲线 |
| Curve | `1 - exp(-4.5t)·cos(9.425t)` | 指数衰减余弦 |
| Stack 顺序 | Card → 胶囊 → 图标 | 固定 |
| Selected icon | primary 实色 | |
| Capsule 颜色 | primary@20% | |
| Inactive icon | primary@40% | |
