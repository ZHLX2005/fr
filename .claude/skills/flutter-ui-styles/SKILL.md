---
name: flutter-ui-styles
description: Flutter 项目中"样式"相关工程的渐进式披露指南。当用户要做 UI 样式选型、视觉对齐复刻、docs/prototypes HTML mockup 与 Flutter 双向对照、或在 Material 3 体系下选某一类样式（顶部 App Bar / Card / Button / NavigationBar / Modal / 浮卡 / 托盘分段 / 大厅就绪等）落地时触发。本 skill 是样式大类的总入口，方案按 A/B/C 序列编号登记在分类索引表里，按需加载。也用于把"看起来像 demo"的内容列表页改造成商店形态，并承载小豆子 FR 的 UI 设计原则（功能型 vs 内容型、border-emphasis、Zen 少描边、胶囊 vs 方圆角、原型 ColorScheme 契约）。
---

# flutter-ui-styles — Flutter 样式工程渐进式披露

> 本 skill 不在主文档里罗列实现细节。核心是**序列总览 +「样式大类 → 子类方案」索引表**；每条方案独立成 `references/<代号>-*.md`，按需查阅。
>
> HTML 真相源：`docs/prototypes/`（`main-shell-nav` / `feature-list-and-lobby` / `remotetype-input` / `game-surfaces-palettes`）。对照入口 → [[C00-原型对齐路由]]。

---

## 何时使用

- "我要做顶部 Banner + 列表的视觉衔接 / 可拉伸 header / banner 与列表有发丝线"
- "这种样式属于什么大类 / 圆角 mask / Card / Button / NavigationBar / Modal"
- "这个页面还是 demo 形态 / 做成商店那样的列表"
- 给定 `docs/prototypes/*.html` / Figma / 截图，要求用 Flutter 对齐
- Zen 浮卡少描边 / 嵌套托盘实心分段 / 胶囊 vs 方圆角 / 大厅房间就绪
- 询问某段 Flutter 代码属于哪个子类方案

## 何时不触发

- 业务逻辑、网络、状态管理、路由 → 别的 skill
- 主题 token / ColorStrategy 架构本身 → `flutter-ui-theme-architecture`（本 skill 管「颜色用在哪里」）
- 动画 timeline / 物理细节 → `flutter-work-flow` 等
- 编译失败 / crash → `flutter-debug-logging` / `bug-detective`

---

## 核心原则（主文档承担，不在 ref 里）

### 先定性：功能型页面 vs 内容型页面

**同一条配色/权重规则在两类页面上结论相反，先定性再选方案。**

| 页面性质 | 条目是什么 | 策略 |
|---|---|---|
| **功能型**（工具、表单、设置、密集按钮区） | 操作 | **减负**：统一主题色 + border-emphasis → [[A01-边框强调式减负]]；Zen 列表浮卡 → [[A06-Zen浮卡少描边]] |
| **内容型**（游戏中心、媒体库、作品集、模板市场） | 作品 | **给身份**：专属封面/渐变 → [[A04-商店式内容页]]；色随主题 → [[C01-游戏表面ColorScheme契约]] |

把内容型页面按功能型做（统一占位 icon + 一律描边不填充）→ "demo 形态"。

### 视觉权重：填充只在该减负的地方减

密集操作区：border-emphasis（[[A01-边框强调式减负]]）。封面 / Hero / 仪式胶囊 CTA：该填充就填充（[[A08-胶囊与方圆角CTA]]）。

### 颜色决策：三分，不是二分

- **导航 / 功能入口** → 统一 `colorScheme.primary`（及 container）
- **操作按钮** → 撞色编码语义（主/查/停/危…）
- **内容条目** → 专属识别色（`const_xxx.dart` slug 表）+ 游戏表面走 [[C01-游戏表面ColorScheme契约]]

### 异步数据加载：必须用 loading flag 保护

嵌套 sheet 异步加载 → [[B01-嵌套sheet异步加载防race]]。

### 反模式黑名单

- ❌ 导航/功能入口 icon 彩虹独立色（内容条目反过来要有专属色）
- ❌ 操作按钮一律主题色（应撞色编码）
- ❌ 内容列表统一占位 icon 当封面
- ❌ 折叠头部浅 `surface` 接深色 banner
- ❌ 把「避免纯色填充」当成全局禁令
- ❌ `withOpacity`（用 `withValues(alpha:)`）
- ❌ 破坏性操作去掉红色
- ❌ 嵌套 sheet `fire-and-forget` 异步加载
- ❌ 工具页 chrome 一律全胶囊（远程输入原型明确反对；见 [[A08-胶囊与方圆角CTA]]）
- ❌ 游戏表面硬编码 Zen sage/clay hex（见 [[C01-游戏表面ColorScheme契约]]）
- ❌ lottery 相关 → 已迁 tool-isolation

---

## 序列总览（先读这里）

| 代号 | 类别 | 何时读该序列 | 入口 / 成员 |
| --- | --- | --- | --- |
| A | 样式方案 SOP | 动手做某种样式 / 选方案前 | [[A00-样式方案路由]] → A01–A09 |
| B | 排障 bug 模式 | 嵌套 sheet race 等 | [[B01-嵌套sheet异步加载防race]]（单成员，无 B00） |
| C | 原型 ↔ Flutter 契约 | HTML 对齐 / 五主题游戏表面 | [[C00-原型对齐路由]] → [[C01-游戏表面ColorScheme契约]] |

---

## 何时读哪个 ref

| 代号 | ref | 何时读取 |
| --- | --- | --- |
| A00 | [[A00-样式方案路由]] | 不确定 A 序列读哪份时先看 |
| A01 | [[A01-边框强调式减负]] | 密集按钮减负 / 左重右轻 / 装饰 vs 功能色 |
| A02 | [[A02-可拉伸banner带圆角mask]] | 顶部可拉伸 Banner + 圆角接列表 |
| A03 | [[A03-胶囊浮动底部导航]] | 主壳胶囊底栏 / capacity / 溢出 sheet |
| A04 | [[A04-商店式内容页]] | 游戏中心等**内容型**列表；程序化封面 |
| A05 | [[A05-批量subagent检查]] | 批量给 lab/demos 做样式扫改 |
| A06 | [[A06-Zen浮卡少描边]] | 茶禅浮卡、少描边、设置/peer 列表 |
| A07 | [[A07-嵌套托盘与实心分段]] | 远程输入式托盘 + 实心滑动分段 |
| A08 | [[A08-胶囊与方圆角CTA]] | 全胶囊 vs 12–20 方圆角判决 |
| A09 | [[A09-大厅与房间就绪]] | 象棋大厅入口 / 房间就绪 / 匹配转场 |
| B01 | [[B01-嵌套sheet异步加载防race]] | 嵌套 ModalBottomSheet 异步 race |
| C00 | [[C00-原型对齐路由]] | 从 `docs/prototypes` 选对照方案时 |
| C01 | [[C01-游戏表面ColorScheme契约]] | 五主题游戏表面禁写死 hex |

> 新方案：在 `references/` 建 `<代号>-<slug>.md`（A 从 A10、B 从 B02、C 从 C02），结构为**一、实现思路** + **二、踩坑总结**，并在上表与对应 `*00` 路由表登记。方案文件 ≤ 200 行。

---

## 添加新方案的标准流程

1. 判定序列：控件配方 → A；运行时坑 → B；原型/主题契约 → C（先读对应 `*00`）
2. 创建 `references/<代号>-<slug>.md`，两节结构，≤ 200 行
3. 登记「序列总览」成员列（若新序列）+「何时读哪个 ref」+ `*00` 路由表
4. 若引用原型，写清 `docs/prototypes/<file>.html`；`lib/` 示例禁裸 hex

结构演化 / 拆 ref / 同步事实 → 用 `key_board`（X01/X02/X03），本 skill 不改自己的核心原则除非用户授权。

---

## 协作 skill

- `key_board`：本 skill 的 ref 生命周期（序列号 A/B/C）
- `flutter-ui-theme-architecture`：ColorStrategy / scheme 派生
- `flutter-work-flow`：build / lint / format
- `subagent-driven-development`：并行落地；本 skill 只提供方案知识

---

### [2026-07-26] key_board 操作教训

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| 把"避免纯色填充"写成无边界全局原则 | 内容页全变成占位卡 | 先分功能型/内容型 |
| 颜色决策只做装饰/功能二分 | 内容条目失去识别色 | 三分：导航 / 操作 / 内容 |
| 新增反向方案后旧 ref 不改边界 | 两份文档互殴 | 旧 ref 加适用边界并互链 |

### [2026-10-12] 原型沉淀（key_board X01 + 序列号）

| 操作 | 结果 |
|---------|---------|
| 阅读 `docs/prototypes` 四份 HTML | 沉淀 A06–A09 + C00/C01；补 A00；A03/A04 增量互链 |
| 序列划分 | A=方案 SOP，B=排障，C=原型契约；多成员序列用 `*00` 元数据入口 |
