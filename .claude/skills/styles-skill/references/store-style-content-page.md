---
name: store-style-content-page
description: 内容列表页样式 · 子类方案 —— 商店式内容页（程序化封面 + 横向精选 + 头部收拢成 AppBar）。一节"实现思路"给落地流水线；二节"踩坑总结"记本方案踩过的真坑。
---

# Store-Style Content Page（商店式内容页）

> 分类：样式大类 = **内容列表页 / Content Index**，子类 = **Store-Style Content Page**。
>
> 何时读：做游戏中心 / 媒体库 / 作品集 / 插件市场这类**内容型**列表页，或要把"一堆长得一样的占位卡"改成有识别度的商店形态时。
>
> 落地代码：`lib/screens/profile/lab/game_center_page.dart` + `game_center/`（const / artwork / cards 三件套）。

**核心判断**：内容型页面 ≠ 功能型页面。功能型（工具、表单、密集按钮区）要**减负**（见 [[border-emphasis-style]]）；内容型要**给每条内容视觉身份**。没有身份 = demo 感。

---

## 一、实现思路

### Step 0 · 先定性：这页是内容型还是功能型

| 页面性质 | 判据 | 配色策略 |
|---|---|---|
| 功能型 | 条目是"操作"（按钮、开关、设置项） | 统一主题色 + border-emphasis 减负 |
| 内容型 | 条目是"作品"（游戏、文章、媒体、模板） | **每条内容专属色**，靠封面建立层次 |

判错方向，后面全白做。

### Step 1 · 视觉身份登记表（const_xxx.dart）

把每条内容的身份收进一张**以稳定 ASCII key（slug）为索引**的常量表，UI 只读表、不写死：

```dart
class GameMeta {
  const GameMeta({
    required this.categories,   // 多归属：Set，不是单个 String
    required this.icon,
    required this.gradient,     // 专属渐变（两色）
    required this.mode,         // 玩法/类型短标签："联机双人"
    this.pattern = GameArtPattern.blob,
  });
  bool get isOnline => categories.contains(GameCategory.multiplayer);
}

const Map<String, GameMeta> kGameMeta = {
  'gomoku-lua': GameMeta(
    categories: {GameCategory.multiplayer, GameCategory.board},
    icon: Icons.grid_4x4_rounded,
    gradient: [Color(0xFF0F766E), Color(0xFF14B8A6)],
    mode: '联机双人',
    pattern: GameArtPattern.grid,
  ),
  // ...
};

GameMeta gameMetaOf(String slug) => kGameMeta[slug] ?? kFallbackGameMeta;
```

要点：
- **按 slug 不按 `is XxxDemo`**：常量层零依赖实现文件，增删内容不牵动 import 图。
- **必须有 fallback**：忘登记的新条目不白板、不崩。
- **分类用 Set 多归属**：`联机五子棋` 同时进「联机」和「棋游」，单归属放不下。

### Step 2 · 程序化封面（没有美术资源也不能长得一样）

四层叠加，顺序固定：

```
① 专属渐变底（LinearGradient topLeft→bottomRight）
② CustomPainter 装饰图案（blob / stripes / grid / dots / wave，白色 alpha 0.07~0.16）
③ 压暗蒙版（顶 0.06 → 底 0.30；有用户自定义图时加深到 0.28 → 0.55）
④ 主图标居中（白色 alpha 0.92）
```

用户设过自定义图时，用图替换 ①②、蒙版加深——**蒙版是让上层白字在任何底图上可读的唯一保障**，不能省。

### Step 3 · 顶部横向精选（PageView）

```dart
PageController(viewportFraction: 0.88)   // 露出下一张的边，暗示可横滑
PageView.builder(
  padEnds: false,                        // 首张贴左边距，不居中留白
  onPageChanged: (i) => setState(() => _featuredIndex = i),
  itemBuilder: (_, i) => Padding(
    padding: EdgeInsets.fromLTRB(i == 0 ? 16 : 6, 4, i == last ? 16 : 6, 10),
    child: FeaturedCard(...),
  ),
)
```
配一排指示点（选中态拉长成 18×6 胶囊）。精选只在"全部"筛选下出现，切到具体分类就收起——否则同一条内容上下重复两次。

### Step 4 · Hero 头部收拢成 AppBar（同源渐变）

目标：滚动过程看起来是"banner 收拢成头部"，而不是"蓝头部滑走、浅色新头部淡入"。

```dart
// ① 渐变只写一处，头部与 AppBar 共用
LinearGradient _headerGradient(ColorScheme scheme) {
  final hsl = HSLColor.fromColor(scheme.primary);
  final base = hsl
      .withSaturation((hsl.saturation * 0.60).clamp(0.0, 1.0))  // 降饱和
      .withLightness(hsl.lightness.clamp(0.30, 0.44));          // 深浅主题都够暗
  return LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [base.toColor(),
             base.withLightness(base.lightness + 0.05).toColor()],  // 只差 5% 亮度
  );
}

// ② Scaffold 让 body 穿到 AppBar 底下
Scaffold(extendBodyBehindAppBar: true, appBar: AppBar(
  backgroundColor: Colors.transparent,
  foregroundColor: Colors.white,          // 恒白：AppBar 永远压在同一片深色上
  elevation: 0, scrolledUnderElevation: 0,
  flexibleSpace: IgnorePointer(child: Opacity(
    opacity: _titleReveal,
    child: SizedBox.expand(                // ← 必须，见坑 1
      child: DecoratedBox(decoration: BoxDecoration(gradient: _headerGradient(scheme))),
    ),
  )),
  title: Opacity(opacity: _titleReveal, child: const Text('游戏中心')),
));

// ③ 滚动进度：淡入距离 = Hero 头部高度，头部正文滑出的同一刻 AppBar 补齐同色
_titleReveal = (controller.offset / kHeaderHeight).clamp(0.0, 1.0);
```

头部内容只留**标题 + 一行小字概览**（`9 款 · 联机 3 · 收藏 2`）。统计做成一排大胶囊 = 无用信息占主位。

### Step 5 · 自适应网格

```dart
SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 210, childAspectRatio: 0.80,
  mainAxisSpacing: 14, crossAxisSpacing: 14,
)
```
用 MaxCrossAxisExtent 不用 crossAxisCount：手机 2 列、平板/折叠屏自动 3~4 列，零分支。

### 验收 checklist

- [ ] 每条内容的封面彼此可辨（不是同一个占位 icon）
- [ ] 滚动全程 AppBar 无色系突变，标题与底色同步淡入
- [ ] 头部高度 ≤ 100，不喧宾夺主
- [ ] 精选横滑露出下一张的边，指示点跟手
- [ ] 平板宽度下网格自动增列，不出现超宽卡
- [ ] 分类 chip 数量与实际分桶一致（含收藏实时刷新）

---

## 二、踩坑总结

### 坑 1 · `flexibleSpace` 里无 child 的 `DecoratedBox` 塌成 0 高

**现象**：滚动后 AppBar 整块透明，内容直接从底下穿过去。

**根因**：AppBar 把 flexibleSpace 放进 `Stack(fit: StackFit.passthrough)`（SDK `app_bar.dart` ~1199 行），传下来的是**松约束**；`DecoratedBox` 无 child 时取 `constraints.smallest` → 高度 0，渐变根本没画。

**结论**：flexibleSpace 里的装饰层必须显式撑开——`SizedBox.expand(child: DecoratedBox(...))`。同理 `Container(decoration:)` 无 child 也塌。

### 坑 2 · 折叠后的 AppBar 用 `scheme.surface` 接住深色 banner

**现象**：下滑过程中蓝色头部滑走、浅色 AppBar 淡入，交界处色系对撞，很突兀。

**根因**：把 AppBar 当"另一个组件"配色，而不是"头部滑走后补上的那一截"。

**结论**：两处共用同一个 `_headerGradient()` 函数（不是复制两份颜色），前景恒白。淡入距离取头部高度，让"补色"与"头部消失"同步。

### 坑 3 · 头部太高 + 统计信息太大

**现象**：banner 占掉近半屏，三个统计胶囊比游戏卡还抢眼。

**结论**：头部是背景不是主角。高度压到 76，统计压成一行 `labelSmall`。数量是参考信息，不配拥有视觉主位。

### 坑 4 · `primary → tertiary` 双色相全饱和渐变太艳

**根因**：两个不同色相 + 满饱和 = 彩虹感，且深浅主题下亮度不可控。

**结论**：从 `primary` 推导单色相——饱和 ×0.60、亮度夹 `0.30~0.44`、两端只差 5% 亮度。彩色投影同理换成黑色低 alpha（`primary/0.22` → `黑/0.10`）。

### 坑 5 · 统一分类占位 icon = demo 感的根源

**现象**：9 张卡用同一个 `Icons.sports_esports` 占位，列表像未完成的脚手架。

**结论**：没有美术资源不是借口。渐变 + 图案 + 图标三件套足以生成可辨识封面（Step 2）。**"看起来像 demo"绝大多数时候是内容缺少视觉身份，不是布局不够花哨。**

### 坑 6 · 别名 slug 导致同一条内容渲染多张卡

**根因**：注册表允许一个实例挂多个 slug（历史兼容 / 别名路由），`getAll()` 返回全部条目。

**结论**：UI 渲染前按**实例**去重（`where(seen.add)`），路由查询才用全量。

### 坑 7 · 分类单归属放不下跨类内容

**现象**：`联机五子棋` 放「联机」就不在「棋游」里，放「棋游」用户在「联机」找不到。

**结论**：`categories` 用 `Set<String>`，一条内容可进多个桶；"本地版"与"联机版"靠是否含 `multiplayer` 区分，而不是靠两个互斥分类。
