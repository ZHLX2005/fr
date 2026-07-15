---
name: styles-skill
description: Flutter 项目中"样式"相关工程的渐进式披露指南。当用户要做 UI 样式选型、视觉对齐复刻、画布/HTML mockup 与 Flutter 实现的双向对照、或在 Material 3 体系下选某一类样式（顶部 App Bar / Card / Button / NavigationBar / Modal 等）落地时触发。本 skill 是样式大类的总入口，所有方案的最终形态都登记在分类索引表里，按需加载对应方案文件。同时承载小豆子 FR 项目的 UI 设计原则与实战 bug 沉淀（border-emphasis 边框强调式、嵌套 sheet race condition、多风格 lottery 投票挑选、纯色按钮减负、左重右轻、装饰性 vs 功能性颜色决策）。
---
---

# styles-skill — Flutter 样式工程渐进式披露

> 本 skill 不在主文档里罗列实现细节。它的核心是**一张"样式大类 → 子类方案"索引表**，每条方案都独立成文件，按需查阅即可。

---

## 何时使用

- "我要做顶部 Banner + 列表的视觉衔接 / 想用 Flutter 实现一个可拉伸 header / 我的 banner 与列表有发丝线"
- "这种样式属于什么大类 / 圆角 mask 怎么做 / masked widget 怎么放"
- "我要做一个 Card / Button / NavigationBar / Modal 类样式"
- 给定 HTML / Figma mock / 截图，要求 1:1 用 Flutter 复刻
- 询问某段 Flutter 代码属于样式大类里的哪个子类

## 何时不触发

- 业务逻辑、网络请求、状态管理、路由 → 别的 skill
- 动画 timeline / 物理 / 缓动细节 → `flutter-work-flow` 或自定义动画 skill
- 编译失败 / 运行时 crash → `flutter-debug-logging` / `bug-detective`
- 性能调优（repaint / jank / memory） → 自带 perf skill（如有）

---

## 核心原则（主文档承担，不在 ref 里）

### 视觉权重：避免纯色填充

填充式（`LinearGradient` / 饱和 `backgroundColor + white`）视觉重、密集按钮区"左重右轻"。
改造为 **border-emphasis**：浅 tint 底 + 同色描边 + 同色前景。详见 [[border-emphasis-style]]。

### 颜色决策：装饰性 vs 功能性（规则相反）

- **装饰性**（导航卡片 icon、菜单项、纯展示）→ **统一主题色** `Theme.of(context).colorScheme.primary`
- **功能性**（操作按钮）→ **撞色编码语义**：green=主操作、blue=查询、orange=暂停、red=危险、indigo=备用

详见 [[border-emphasis-style]] 的"颜色决策"章节。

### 异步数据加载：必须用 loading flag 保护

嵌套 sheet 中（`ModalBottomSheet → ModalBottomSheet`），`initState` 里 `fire-and-forget` 调异步加载（SharedPreferences、网络），用户在加载完成前就点进下一层 sheet → 看到空数据 → 误以为"没有找到"。必须 `_loadingXxx` flag + try/finally + mounted 检查 + picker 守卫。详见 [[async-load-flag-pattern]]。

### 反模式黑名单

- ❌ 给导航卡片配彩虹独立色（应统一主题色）
- ❌ 给操作按钮统一主题色（应撞色编码）
- ❌ `withOpacity(x)`（analyze 报 deprecated_member_use，应 `withValues(alpha: x)`）
- ❌ 删除/取消按钮去掉红色（破坏性操作永远保留 red）
- ❌ 嵌套 sheet 里 `fire-and-forget` 异步加载（race condition 必现）
- ❌ lottery 后续轮重新询问"你要什么风格"（应直接看保留文件推断偏好）
- ❌ 让 lottery subagent 把代码/内容贴回聊天（上下文爆炸，应只写文件）

---

## 分类索引（按需加载）

| 样式大类 | 子类方案 | 何时读 | 方案文件 |
|---|---|---|---|
| **Top App Bar / Banner Header** | Banner Stretch with Rounded Mask | 做 "顶部可拉伸 Banner + 圆角接列表" 时 | [[banner-stretch-rounded-mask]] |
| **Bottom Bars** | Floating Pill Bottom Nav | 做"固定宽胶囊容器 + 滑动胶囊指示器"的悬浮式底部导航时 | [[floating-pill-bottom-nav]] |
| **按钮 / Icon 容器 — 视觉减负** | Border-Emphasis 边框强调式 | 改造纯色填充按钮/icon 容器 / 减负密集按钮区 / "左重右轻" / 装饰性 vs 功能性颜色决策 | [[border-emphasis-style]] |
| **嵌套 sheet 异步加载** | Async Load Flag Pattern | 嵌套 ModalBottomSheet 异步加载 race condition（"空空如也"/缓存竞态）；必须 `_loadingXxx` flag + try/finally + mounted 检查 + picker 守卫 | [[async-load-flag-pattern]] |
| **多风格挑选流程** | Style Lottery | 用户说"生成 N 套不同风格让我挑"/"再生成几个备选"/多轮迭代挑选 | [[lottery-workflow]] |

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
