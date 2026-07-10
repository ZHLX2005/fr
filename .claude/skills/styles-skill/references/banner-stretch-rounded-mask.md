---
name: banner-stretch-rounded-mask
description: 顶部 App Bar 样式 · 子类方案 —— 可拉伸 Banner + 圆角 mask 衔接列表。一节"实现思路"给落地流水线；二节"踩坑总结"记本方案踩过的所有真坑与最终结论。
---

# Banner Stretch with Rounded Mask

> 分类：样式大类 = **Top App Bar / Banner Header**，子类 = **Banner Stretch with Rounded Mask**。

视觉目标（一句话）：顶部一张可点击的大图/渐变 banner，下拉 overscroll 时整个 banner 区域被拉伸成弹性区域再回弹，banner 与下方列表之间是**无可见接缝的圆角过渡**，列表背景色"贴进"AppBar 下方。

落地代码段参考 `lib/screens/profile/profile_page.dart`（search: `flexibleSpace`）。

---

## 一、实现思路

### Step 1 · 搭可拉伸顶栏骨架

```dart
Scaffold(
  backgroundColor: Theme.of(context).colorScheme.surface,   // 兜底任何透明缝
  body: SafeArea(
    top: false,                                              // 让 SliverAppBar 消化顶部安全区
    child: CustomScrollView(
      physics: const BoundedBouncingScrollPhysics(          // 项目自带，限幅 80 px
        parent: AlwaysScrollableScrollPhysics(),
        maxOverscroll: 80,
      ),
      slivers: [
        SliverAppBar(
          expandedHeight: 200,   // banner 自身可见高（不是 AppBar 区域总高）
          pinned: true,
          floating: false,
          snap: false,
          stretch: true,         // 顶部 overscroll 拉高整个 AppBar 区域
          // flexibleSpace 见 Step 2
        ),
        // SliverToBoxAdapter 见 Step 4
      ],
    ),
  ),
);
```

### Step 2 · flexibleSpace 改用 Stack，外层塞 FlexibleSpaceBar + 圆角盖

```dart
flexibleSpace: Stack(
  fit: StackFit.expand,
  clipBehavior: Clip.none,        // 关键：允许圆角盖探出 AppBar 底边可见
  children: [
    FlexibleSpaceBar(
      title: _bannerPath == null ? const Text('小豆子') : null,
      titlePadding: const EdgeInsets.only(left: 16, bottom: 40),
      background: SpringyBanner(                      // 自定义，banner + 点击 + fallback
        imagePath: _bannerPath,
        fallback: _buildDefaultBanner(context),
        onTap: _showBannerOptions,
      ),
    ),
    // 圆角盖：放外层 Stack（不是 FlexibleSpaceBar.background 里）
    Positioned(
      left: 0, right: 0,
      bottom: -12,                                    // 关键：向下探 12 px
      height: 36,                                     // 24(原弧顶区) + 12(下探覆盖)
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(24),
          ),
        ),
      ),
    ),
  ],
),
```

**为什么外层 Stack？** `FlexibleSpaceBar.zoomBackground` 默认 stretch 时把 `widget.background` 整体高度从 `maxExtent` 拉到 `maxHeight`（SDK 源 `packages/flutter/lib/src/material/flexible_space_bar.dart` 行 255-275）。如果把圆角盖放在 background 内，它会被一起拉高 → mask 底边 ≠ SliverAppBar 真实 layout 底边 → 与下方 body 错位。**放外层 Stack 是兄弟节点 → 不受 zoomBackground 影响 → bottom 永远钉真实底边。**

### Step 3 · 加 list，列表底色上探 12 px 兜底"上滑"静态缝

```dart
SliverToBoxAdapter(
  child: Transform.translate(
    offset: const Offset(0, -12),                     // 列表整块上移 12 px
    child: Container(
      color: Theme.of(context).colorScheme.surface,   // 把原透明顶部填实 surface
      child: Padding(
        padding: const EdgeInsets.only(top: 12),      // 补回视觉位置
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const SizedBox(height: 16),
              _buildMenuCard(...),
              // ...其余卡片 + 彩蛋不变
            ],
          ),
        ),
      ),
    ),
  ),
),
```

**为什么上滑静态缝靠 body 上探？** pinned SliverAppBar 画在 body 之上，上滑到顶时 body 顶端 = AppBar 底边，两条 AA 边（mask 下边 + body 上边）在同一像素行各 50% 覆盖率 → 发丝线。`Transform.translate(-12)` 让 body 顶端往上探 12 px 与 mask 重叠 → 该行变实心 surface → 缝消失。

**为什么下拉动态缝 body 上探无效？** 下拉 stretch 时 mask 跟 AppBar 一起拉高，body 也下移，但位移路径不同 → 瞬时错位 2~3 px。pinned AppBar 仍画在 body 之上 → body 顶端无论怎么探都够不着 AppBar 底边的缝 → 这条缝由 Step 2 的 mask 下探 12 px 兜底。

### Step 4 · 验收

- [ ] 下拉 stretch：banner 渐变被拉伸，松手有 iOS 弹性回弹（80 px 限幅）
- [ ] 静态接缝无发丝线（Scaffold surface + mask 覆盖生效）
- [ ] 下拉过程中接缝无发丝线（mask 下探 12 px 生效）
- [ ] 上滑到顶再上滑：接缝无发丝线（body 上探 12 px + Container surface 生效）
- [ ] 点击 banner：回调触发（crop / remove sheet）
- [ ] Scaffold 背景色与列表 / 圆角盖三色完全一致

---

## 二、踩坑总结

> 本节列出的都是本方案真实踩过的坑，按发现顺序排列，每条说明"现象 → 根因 → 最终结论"。

### 坑 1 · mask 高度 = 圆角 → "看不出弧"

**现象**：mask 高 24、圆角 24，圆弧视觉上几乎是一条直线。

**根因**：`border-radius` 在 Flutter / CSS 都会被自动裁到 `min(r, h/2)`。h=24、r=24 → 实际半径 = min(24, 12) = **12**。

**结论**：mask 高度至少 `2 × 圆角半径`。本方案 mask 高 36、目标圆角 24 → 实际半径 = min(24, 18) = **18**。比完整 24 略扁，可接受（弧顶完整可见，只是弧度扁一点）。要严格 24 半径则 mask 高 ≥ 48。

### 坑 2 · `Transform.translate` 在 sliver 链里失效

**现象**：把 mask 移到 `SliverToBoxAdapter` 顶部，外层 `Transform.translate(Offset(0, -20))`。运行后 mask 位置完全不变。

**根因**：`RenderSliverToBoxAdapter` 在 paint 阶段重置子节点的 paint offset 到 `geometry.paintOrigin`（由 sliver chain 计算），box-level Transform 被吞掉。

**结论**：别在 `SliverToBoxAdapter`（或其他 sliver widget）内尝试用 Transform 移动子 widget。要跨界位移，**必须把 widget 放到它要跨越的边界那一侧**（本方案就是放回 `flexibleSpace` 外层 Stack 内）。

### 坑 3 · `Positioned(top: 负值)` 在 sliver 链里也失效

**现象**：同上，改用 `Stack(clipBehavior: Clip.none)` + `Positioned(top: -20)`。mask 仍紧贴 SliverToBoxAdapter 顶部。

**根因**：同坑 2，`Positioned` 也是改 box-level paint offset，被 sliver paint 重置。

**结论**：跨界位移必须靠**重新放置 widget 本身**，而非调整局部 paint。

### 坑 4 · mask 放在 `FlexibleSpaceBar.background` 内 → 下拉露 banner 缝

**现象**：把 mask 放 `FlexibleSpaceBar.background` 内 `Stack` 的 `Positioned(bottom: -20, height: 68)`。下拉 overscroll 时接缝处**露出 banner 渐变**（不是 Scaffold 底色）。

**根因**：`zoomBackground` 把 `widget.background` 整体高度从 `maxExtent` 拉到 `maxHeight`，**background Stack 整体拉高** → Stack 内 `Positioned(bottom: -20)` 是相对拉伸后的 Stack 底边；mask 底边 ≠ SliverAppBar 真实 layout 底边 → 与下方 body 错位 → 缝背后露出 banner 渐变。

**结论**：mask 必须在 `flexibleSpace` 外层 Stack，与 `FlexibleSpaceBar` 平级。详见坑 5。

### 坑 5 · Stack 默认 clip → mask 探出部分被裁

**现象**：mask `bottom: -12` 时，探出 AppBar 底边的 12 px 看不见。

**根因**：`Stack` 默认 `clipBehavior: Clip.hardEdge`，超出 Stack 边界的子节点被裁。

**结论**：外层 `Stack` 必须显式 `clipBehavior: Clip.none`，否则 mask 下探没用。

### 坑 6 · `Scaffold` 默认背景色 ≠ `colorScheme.surface`

**现象**：上滑到顶接缝处透出比 surface 略深的色（看起来像"接缝"）。

**根因**：M3 默认 `scaffoldBackgroundColor` ≠ `colorScheme.surface`，两者色阶差一档。

**结论**：显式 `Scaffold(backgroundColor: Theme.of(context).colorScheme.surface)` 兜底。这一步本身不修发丝线（根因是 AA 叠加半透明），但消除了"缝背后是不同色"的错觉。

### 坑 7 · 接缝发丝线根因是 AA 叠加，不是颜色

**现象**：解决了坑 6 后接缝**仍**可见。比 surface 略暗的线。

**根因**：mask 下边（AA 50%）+ body 上边（AA 50%）在同一像素行 → 总覆盖率 < 100% → 半透明 → 略暗的发丝线。

**结论**：要消除，要么**消除其中一条边**（mask 重叠在 body 上 = 没有 body AA 上边；body 上探 = 没有 body AA 上边），要么**让两条边重合在实心 color 上**（mask + body 都 surface 实心，颜色一致在视觉上抹平）。本方案两个方向都做：mask 下探 12 px 压 body 上探 12 px，1 px 厚的"夹心区"两侧都是 surface、上下都覆盖。

### 坑 8 · `1px` 上探修不了"下拉"动态缝

**现象**：`Transform.translate(Offset(0, -1))` 修了上滑静态缝，下拉过程中仍偶发可见 0.5 px 缝。

**根因**：stretch overscroll 时 mask 拉高、body 偏移，两个位移路径由不同计算步骤得出 → 取整不同步 → 瞬时错位 **2~3 px**。1 px 探出覆盖不住。

**结论**：body 上探量提到 ≥ 12 px（经验值，覆盖绝大多数设备 / DPR / stretch 速度）。本方案 12 px。

### 坑 9 · body 上探 12 px 对下拉无效（关键认知）

**现象**：body 上探 12 px，下拉过程中仍偶发漏缝，与上探 1 px 几乎无差别。

**根因**：**pinned SliverAppBar 画在 body 之上**。body 在 AppBar 底下，无论怎么探都够不着 AppBar 底边那一行的缝。`Scaffold` 里列表上滑时"钻进 AppBar 底下消失"就是这层叠序的证据。

**结论**：body 上探只能修**上滑**那侧；**下拉**的缝必须由**上层**的 mask 探出（`Positioned(bottom: -N)`）兜底。这才是最终修复路径。

### 坑 10 · mask 高度 = 24, 圆角 = 24 → 圆弧看起来很弱（已合并坑 1）

最终 mask 高 36、目标圆角 24 → 实际半径 18，弧度略扁但**稳定无漏**。两全其美需 mask 高 48 + 减少下探量 → 失去缝修复。

---

## 验收 checklist

```text
[ ] 静止时弧顶可见（即使弧度比 24 略扁也 OK）
[ ] 下拉 stretch：banner 渐变被拉伸，回弹有 80 px 限幅
[ ] 下拉过程中接缝无发丝线
[ ] 上滑到列表顶再上滑：接缝无发丝线
[ ] 点击 banner 触发回调
[ ] 主题切换（粉红 / dark）时三色（scaffold / mask / body 顶部）保持一致
```

---

## 已废弃变体（不要重启）

| 变体 | 为什么不要 |
|---|---|
| SliverAppBar 内部 `Positioned(bottom: 0, height: 24)`（不凸进不下探） | 上滑静态缝能修，但下拉动态 2~3 px 缝漏 |
| `expandedHeight: 224 = 200 + 24` 留 mask 让位 | mask 不再凸进 banner，让位是浪费 |
| `Stack(ClipRRect(circular(24)))` 直接盖 FlexibleSpaceBar 整体 | zoomBackground 仍然拉高 ClipRRect 的 sourceRect，圆角变形 |
| `RenderSliver` 自定义类 | 维护成本高，本方案用 widget 层组合已能根治 |
| 1 px 上探 / 1 px 下探 | 不够（坑 8、9） |
