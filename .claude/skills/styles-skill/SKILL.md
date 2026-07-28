---
name: styles-skill
description: Flutter 项目中"样式"相关工程的渐进式披露指南。当用户要做 UI 样式选型、视觉对齐复刻、画布/HTML mockup 与 Flutter 实现的双向对照、或在 Material 3 体系下选某一类样式（顶部 App Bar / Card / Button / NavigationBar / Modal 等）落地时触发。本 skill 是样式大类的总入口，所有方案的最终形态都登记在分类索引表里，按需加载对应方案文件。也用于把"看起来像 demo"的内容列表页（游戏中心 / 媒体库 / 作品集）改造成商店形态——程序化封面、横向精选、头部收拢成 AppBar。同时承载小豆子 FR 项目的 UI 设计原则与实战 bug 沉淀（功能型 vs 内容型页面分治、border-emphasis 边框强调式、嵌套 sheet race condition、多风格 lottery 投票挑选、左重右轻、三分颜色决策）。
---
---

# styles-skill — Flutter 样式工程渐进式披露

> 本 skill 不在主文档里罗列实现细节。它的核心是**一张"样式大类 → 子类方案"索引表**，每条方案都独立成文件，按需查阅即可。

---

## 何时使用

- "我要做顶部 Banner + 列表的视觉衔接 / 想用 Flutter 实现一个可拉伸 header / 我的 banner 与列表有发丝线"
- "这种样式属于什么大类 / 圆角 mask 怎么做 / masked widget 怎么放"
- "我要做一个 Card / Button / NavigationBar / Modal 类样式"
- "这个页面还是 demo 形态 / 重构成更专业的 UIUX / 做成商店那样的列表"
- 给定 HTML / Figma mock / 截图，要求 1:1 用 Flutter 复刻
- 询问某段 Flutter 代码属于样式大类里的哪个子类

## 何时不触发

- 业务逻辑、网络请求、状态管理、路由 → 别的 skill
- 动画 timeline / 物理 / 缓动细节 → `flutter-work-flow` 或自定义动画 skill
- 编译失败 / 运行时 crash → `flutter-debug-logging` / `bug-detective`
- 性能调优（repaint / jank / memory） → 自带 perf skill（如有）

---

## 核心原则（主文档承担，不在 ref 里）

### 先定性：功能型页面 vs 内容型页面（最上位的判断）

**同一条配色/权重规则在两类页面上结论相反，先定性再选方案。**

| 页面性质 | 条目是什么 | 策略 |
|---|---|---|
| **功能型**（工具、表单、设置、密集按钮区） | 操作 | **减负**：统一主题色 + border-emphasis → [[border-emphasis-style]] |
| **内容型**（游戏中心、媒体库、作品集、模板市场） | 作品 | **给身份**：每条内容专属封面/渐变/图案 → [[store-style-content-page]] |

把内容型页面按功能型做（统一占位 icon + 一律描边不填充），产出的就是"demo 形态"——
**"看起来像 demo"绝大多数时候是内容缺少视觉身份，不是布局不够花哨。**

### 视觉权重：填充只在该减负的地方减

密集操作按钮区的填充式（饱和 `backgroundColor + white`）视觉重、"左重右轻"，改 **border-emphasis**：
浅 tint 底 + 同色描边 + 同色前景。详见 [[border-emphasis-style]]。

**但这不是全局禁令**：内容封面、Hero 头部、主 CTA 胶囊该填充就填充——
它们的层次正是靠填充与色彩建立的。判据看上一节的页面性质，不要一刀切。

### 颜色决策：三分，不是二分

- **导航 / 功能入口**（菜单卡 icon、tab、纯展示装饰）→ **统一主题色** `colorScheme.primary`
- **操作按钮**（功能性）→ **撞色编码语义**：green=主操作、blue=查询、orange=暂停、red=危险、indigo=备用
- **内容条目**（游戏、媒体、作品、模板）→ **每条专属识别色**，集中登记在 `const_xxx.dart` 的 slug 表里

前两条详见 [[border-emphasis-style]]，第三条详见 [[store-style-content-page]]。

### 异步数据加载：必须用 loading flag 保护

嵌套 sheet 中（`ModalBottomSheet → ModalBottomSheet`），`initState` 里 `fire-and-forget` 调异步加载（SharedPreferences、网络），用户在加载完成前就点进下一层 sheet → 看到空数据 → 误以为"没有找到"。必须 `_loadingXxx` flag + try/finally + mounted 检查 + picker 守卫。详见 [[async-load-flag-pattern]]。

### 反模式黑名单

- ❌ 给**导航/功能入口** icon 配彩虹独立色（应统一主题色）
  ——但**内容条目**反过来：没有专属色才是错的
- ❌ 给操作按钮统一主题色（应撞色编码）
- ❌ 内容列表用统一占位 icon 当封面（demo 感的头号来源，见 [[store-style-content-page]]）
- ❌ 折叠头部用浅色 `surface` 接住深色 banner（滚动中途色系断层）
- ❌ 把"避免纯色填充"当全局禁令套到封面 / Hero 头部上（该有的层次全被抹平）
- ❌ `withOpacity(x)`（analyze 报 deprecated_member_use，应 `withValues(alpha: x)`）
- ❌ 删除/取消按钮去掉红色（破坏性操作永远保留 red）
- ❌ 嵌套 sheet 里 `fire-and-forget` 异步加载（race condition 必现）
- ❌ lottery 后续轮重新询问"你要什么风格"（应直接看保留文件推断偏好）—— lottery 流程已迁到 tool-isolation，详见 [[tool-isolation#lottery-workflow]]
- ❌ lottery subagent 把代码/内容贴回聊天（上下文爆炸，应只写文件）

---

## 分类索引（按需加载）

| 样式大类 | 子类方案 | 何时读 | 方案文件 |
|---|---|---|---|
| **内容列表页 / Content Index** | Store-Style Content Page | 做游戏中心 / 媒体库 / 作品集 / 模板市场这类**内容型**列表页；程序化封面（无美术资源也要每条可辨）、横向精选 PageView、Hero 头部收拢成 AppBar、自适应列数网格；或要把"一堆一样的占位卡"改成商店形态时 | [[store-style-content-page]] |
| **Top App Bar / Banner Header** | Banner Stretch with Rounded Mask | 做 "顶部可拉伸 Banner + 圆角接列表" 时 | [[banner-stretch-rounded-mask]] |
| **Bottom Bars** | Floating Pill Bottom Nav | 做"固定宽胶囊容器 + 滑动胶囊指示器"的悬浮式底部导航时 | [[floating-pill-bottom-nav]] |
| **按钮 / Icon 容器 — 视觉减负** | Border-Emphasis 边框强调式 | 改造纯色填充按钮/icon 容器 / 减负密集按钮区 / "左重右轻" / 装饰性 vs 功能性颜色决策 | [[border-emphasis-style]] |
| **嵌套 sheet 异步加载** | Async Load Flag Pattern | 嵌套 ModalBottomSheet 异步加载 race condition（"空空如也"/缓存竞态）；必须 `_loadingXxx` flag + try/finally + mounted 检查 + picker 守卫 | [[async-load-flag-pattern]] |
| **大规模治理** | Subagent 批量检查 | 需要对整个 lab/demos 目录（或某批 demo）统一做样式改造/检查（如 border-emphasis 转换、去 withOpacity、统一按钮风格）时；适用"批量发现 → 并行修复 → 统一验证"场景 | [[batch-checking-subagent]] |

> 当你要加入**新的样式方案**（例如 Card 自定义、Button 自定义、NavigationBar 自定义等），按相同规范在表里追加一行，并在 `references/` 目录下新增一个方案文件。两文件结构一致：**1. 实现思路** + **2. 踩坑总结**。

---

## 添加新方案的标准流程

1. 在 `references/` 下创建 `<slug>.md`（kebab-case，与 `[[xxx]]` 同名）
2. 文件结构必须分**两节**：
   - **一、实现思路**：落地步骤化、关键代码片段、可直接抄
   - **二、踩坑总结**：本次实操踩出来的真坑（不要写"可能踩坑"，只写真踩过的）
3. 在本 SKILL.md 的"分类索引"表里**追加一行**，注明：
   - 样式大类（如需新增）
   - 子类方案名
   - 一句话触发场景
4. 方案文件 ≤ 200 行

---

## 协作 skill

- 与 `key_board_2` 协作：每个方案文件的"实现思路"小节就是用 `key_board_2` 元模板风格写的
- 与 `subagent-driven-development` 协作：本 skill 不替它执行实现，只提供"该方案对应的 Flutter widget API 与已知坑"的知识
- 与 `flutter-work-flow` 协作：本 skill 给出方案；flutter-work-flow 给出 build / lint / format 等工程流

---

### [2026-07-26] key_board_3 操作教训

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| 把"避免纯色填充"写成**无适用边界**的全局核心原则 | 内容型页面照做 → 9 张卡共用一个占位 icon、零识别度，正是用户投诉的"demo 形态" | 原则必须带适用边界；先分「功能型 / 内容型」再选策略 |
| 颜色决策只做「装饰性 vs 功能性」二分 | 内容条目（游戏/媒体/作品）被归进"装饰性"→ 强制统一主题色 → 无法建立内容身份 | 改三分：导航入口统一色 / 操作按钮撞色 / 内容条目专属色 |
| 新增反向方案的 ref 后，旧 ref 原样保留 | 两份文档互相打架，加载哪份取决于运气 | 新增反向方案时**同步给旧 ref 加"适用边界"段**并双向互链 |
