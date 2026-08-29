# 子 ref B：如何扩展（theme-extension）

> 从 [SKILL.md](../SKILL.md) 导航进入。本文给 **主题系统的扩展与迁移 SOP**：新增配色、新增语义角色、新增组件样式、把既有硬编码迁到主题通道、豁免判定、特例策略怎么写。
> 系统分层/文件地图先看 [[architecture]]；用量现状/热点文件看 [[color-usage-audit]]；识别色锁定业务怎么写看 [[special-cases]]。

## 0. 扩展动作速查表

| 我想… | 动哪些文件 | 详见 |
| --- | --- | --- |
| 新增一套主题配色 | `tokens/color/theme/<new>.dart` + `app_theme.dart`（+可选 `materialThemeModeProvider`） | §1 |
| 新增强调色 / 语义角色（如在 `ColorStrategy` 加 `info`） | `colors/strategy/color_strategy/color_strategy.dart` + `colors/strategy/color_strategy/themes/default.dart`（+ 其他 strategy 如有同类需求） | §2 |
| 新增国际象棋 / 任何"特殊棋类"的色板（两色格 + 选中/将军/升变等）| `tokens/color/<new>/<new>.dart` + `colors/strategy/<new>_color_strategy/` + `extensions/<new>_color_strategy_extension.dart` + `factory.dart` + `app_theme.dart` 注册 + `widgets/context_<new>_colors.dart` | 同 §1 流程，对照 v6.2.1 新增的 `ChessColorStrategy` |
| 新增 / 改一个复用的组件样式 | `component/` 或 `widgets/theme/zen_theme.dart` helper | §3 |
| 把既有硬编码色迁到主题通道 | 迁移 SOP | §4 |
| 写"识别色锁定"特例（玩家靠颜色识别，跨主题不切换） | `tokens/color/<new>/<new>.dart` + strategy + extension + factory + app_theme 注册 + context_*.dart | [[special-cases]] |
| 看历史踩过的反模式 / 找正确做法 | 踩坑经验库 | §4.5 |
| 判断某处能不能写裸 hex | 豁免规则 | §5 |

### 0.1 契约规则（大色块交互卡片）

> **若是大色块卡片，承载交互功能（输入 / 上传 / 选择），卡片背景颜色必须用「淡色主题色」。**

实现：`Color.lerp(theme.colorScheme.surface, theme.colorScheme.primaryContainer, 0.2)` 或更浅（lerp 系数 0~0.3 区间）。

- ✅ 反例：`surfaceContainerHighest`（多数主题偏深）、`primaryContainer`（多数主题仍偏深）、`onSurface`（light 主题是深色，会变黑底）
- ✅ 正例：`Color.lerp(surface, primaryContainer, 0.2)` —— 80% surface + 20% primaryContainer，背景极淡、保留主题色调
- 展示型（图片列表 / 空状态 / 状态栏 / 进度显示）仍可用 `surfaceContainerHighest`，不属于本规则范围
- 拍照框的"已拍照态"用 `colorScheme.onSurface` 深底（衬托图片），属合理用法，不在本规则限制

**踩坑案例**：`lib/lab/demos/notion_image_host_demo.dart` 拍照框 + 文字输入框 → 最初 `surfaceContainerHighest`（太深）→ `primaryContainer`（仍深）→ `Color.lerp(..., 0.4)` → `Color.lerp(..., 0.2)` 才对。

> **"输入/上传/选择" 在 PR review 中需要进一步细化** —— 用户实操把违规范围卡在「输入框 / 表单选择控件」这一严格子集，按钮 / 确认 / 纯展示 / 小头像 / chat 气泡 / 进度槽 等**明确不算**。详见 §4.5.13 用户实操边界白名单。

## 1. 新增一套主题配色

**数据入口两件套必须同步**（缺一不可，否则 `getThemeData` 会缺参）：

1. **`tokens/color/theme/<mode>.dart` → `<Mode>Colors`**：新增 `class` 含 `static const ColorScheme scheme` + `static const AppColorsExtension appColors`。
   - 按「主色族不动 + 环境族染互补 hue（差 150°~170°）+ tertiary 互补强副 + error 保持」设计。
   - onPrimary/onError 等纯黑纯白引用 `RawColors`；环境色注意与主色 hue 对比度。
2. **`app_theme.dart`**：
   - `enum AppThemeMode` 加一个枚举值。
   - `getThemeDisplayName` / `getThemeIcon` 的 switch 各补一支。
   - `getThemeData` 的 switch 加 `_buildTheme(scheme:..., ext:..., cardShadow:...)`（cardShadow 深色主题用 `RawColors.shadowMedium/shadowHeavy`，浅色用 `shadowLight`）。
3. **`state/theme_provider.dart`**：若新主题是深色（`Brightness.dark`），`materialThemeModeProvider` 的 switch 要补 `AppThemeMode.<new> => ThemeMode.dark`，否则浅色主题全落 `_ => light` 分支。

校验：切到新主题整页审一遍（重点：卡片/对话框 surface 对比、正文 onSurface、边框 outline、危险 error）。

> **特例策略不受影响**：`TetrisColorsStrategy` / `TeamAvatarStrategy` 走 native const，新主题下不变。`DefaultTorchProtectStrategy` 切主题会重新派生。

## 2. 扩展语义角色（ColorStrategy）

> 只在该角色**跨页面复用且语义清晰**时才加；角色过多会让 `==`/`hashCode` 和所有实现都变重。默认策略已覆盖 6 核心 + scheme 兜底，多数新需求用 `context.colors.scheme.X` 或 `AppColorsExtension` 就够。

若确需新增（示例：增加 `info` 角色）：

1. `colors/strategy/color_strategy/color_strategy.dart`：抽象加 `Color get info;`，并在 `==`/`hashCode` 中并入 `info`。
2. `colors/strategy/color_strategy/themes/default.dart`：实现 `info => scheme.tertiary`（或选合适 scheme 角色映射）。
3. 如还有 board / torchProtect 策略需要相同角色，照 `default_board_color_strategy.dart` / `default_torch_protect_strategy.dart` 同法扩，并同步它们的 `==`/`hashCode`。
4. 消费端已有 `context.colors` 快捷入口，扩接口后自动可用，无需改 `context_colors.dart`。

> ⚠️ 任何实现 `ColorStrategy` 的类都要满足 `@immutable` + 角色全覆盖 + `==`/`hashCode` 一致性，否则策略去重与 rebuild 失效。
> ⚠️ **特例策略不要扩**：`TetrisColorsStrategy` 4 角色锁定，扩它 = 改 const 引用面 = 高风险。要加识别色业务开新 strategy（见 [[special-cases]] §2）。

## 3. 新增 / 修改组件样式

- **能用内置的，不建新的**：普通按钮/卡片用 `FilledButtonTheme`/`ElevatedButtonTheme`/`CardTheme`（已在 `app_theme.dart` 的 `_buildTheme` 注册，统一从 scheme 派生）。
- **非内置复合样式**（如 hero 圆钮、状态点）：
  - 纯样式 → `lib/core/theme/component/` 下加静态方法（读 `Theme.of(context).colorScheme.X`，不写裸 hex）。
  - 需要 widget 结构 + 样式 → `lib/widgets/theme/zen_theme.dart` 加 helper 或委托 `lib/widgets/base/*`，内部统一 `DefaultColorStrategy.of(scheme)`（与现有 `zenCardTheme` 等一致）。
- 新增 helper 后，在 `color-usage-audit.md` 的相关目录行补一句使用点，保持审计表新鲜。

## 4. 把既有硬编码迁到主题通道（迁移 SOP）

判断当前写法属于哪类，然后一键入对应通道（决策速查见 [[color-usage-audit]] §6）：

| 现状 | 迁到 | 改法 |
| --- | --- | --- |
| `Color(0xFF...)` / `Colors.grey` | `Theme.of(context).colorScheme.X` | 找语义对应的 M3 角色（surface/onSurface/outline/primary/error…） |
| 6 角色语义（accent/surface/outline/text/textMuted/danger） | `context.colors.X` | 直接换，语义 1:1 |
| 棋盘专属 | `context.boardColors.X` | player1/player2/winHighlight…见 §4 表 |
| tetris 棋盘 + 7 方块色 | `context.tetrisColors.X` | `pieceBackground` / `pieceColors[1..7]`（Map 强制 1..7 索引） |
| 团队卡头像 | `context.teamAvatar.avatars[i]` | i = 0..5 |
| 护眼色预设 | `context.torchProtect.presets[i]` | i = 0..9 |
| 状态色 / 分类色 | `Theme.of(context).extension<AppColorsExtension>()!` | `success / warning / info / category[i]` |

**流程**：
1. `grep -rn "Color(0xFF" <dir> --include="*.dart"` 列出待迁点（及 `Color(0x` / `Colors.`）。
2. 迁完跑 §6 校验。
3. 若目录出现成片迁移，回到 `color-usage-audit.md` 迁移历史表登记新批次、更新残留计数。

**命名不带裸 hex 的注意点**：`const` widget / `static const` 里原本用 `Color(0xFF...)` 又要求 const 的，先看能否改读 `ColorScheme` 实例值（const 就放弃，改非 const 或用 `RawColors` 常量）；`Color.lerp` 派生的色允许在策略类内（它们是计算产物不是硬编码）。

## 4.5 踩坑经验库（迁移常见反模式 → 正确做法）

> 本节汇总 v6+ 历次迁移踩过的反模式。每条按"症状 / 根因 / 正确做法 / 案例"组织。**改代码前先扫一遍本节，能省一半调试时间。**

### 4.5.1 ❌ 用 `surfaceContainerHighest` 当 AppBar / Scaffold / 卡片背景

**症状**：AppBar 颜色发暗、页面整体偏深、lemon/rose 等浅色主题下"看起来像没换主题"。

**根因**：`surfaceContainerHighest` 是 M3 的"最抬升容器"，在浅色主题也是**淡灰/淡彩**（不是纯白）；在 dark 主题（purple）则变成**深色底**。把它当 AppBar 背景会把页面压暗。

**正确做法**：用 `surface`（页面/卡片/AppBar/BottomNavBar 的背景标准值）。

**踩坑案例**：`lib/widgets/theme/zen_theme.dart` `zenPageScaffold`、`lib/core/theme/app_theme.dart` `appBarTheme`/`bottomNavigationBarTheme`。

### 4.5.2 ❌ 用 `inversePrimary` 当 AppBar / Scaffold 背景

**正确做法**：直接删掉 `backgroundColor:` 让它走 AppBarTheme 默认值（=`scheme.surface`）。要更深背景 → 用 `surfaceContainer`，不要用 `inversePrimary`。

### 4.5.3 ❌ 用 `surfaceVariant`（已 deprecated）

**正确做法**：换成 `surfaceContainerHighest`（语义最接近：弱化表面）。如果嫌深，再换成 `surface` 或 `surfaceContainerHigh`。

### 4.5.4 ❌ 用 `Color.lerp(color, Colors.white/black, 0.5)` 调淡

**正确做法**：用主题角色：`primaryContainer` / `secondaryContainer` / `tertiaryContainer`（已是该主题的"浅色版本"）。要更淡 → `Color.lerp(surface, primaryContainer, 0.2)`。

### 4.5.5 ❌ Card 背景用 `onSurface`

**正确做法**：Card 背景用 `surface`。`onSurface` 只用于文字/图标前景色。

### 4.5.6 ❌ outline 调成太淡的纯灰

**正确做法**：保留**带主题色温的淡色调**——lemon 用淡柠檬白 `#EAE5D6`、rose 用淡粉白 `#EADEE1`。

### 4.5.7 ❌ Icon container 背景用 `bookmark.color.withAlpha(51)`

**正确做法**：icon container 背景用 `primaryContainer`（选中）或 `surfaceContainerHighest`（未选）；边框用 `primary`/`outline`。

### 4.5.8 ❌ Markdown code 块背景用 `surfaceContainerHighest`

**正确做法**：用 `primaryContainer`（浅主题色块，代码对比度好）。

### 4.5.9 ❌ 修改 ColorScheme 后没核对引用面

**正确做法**：改 ColorScheme 后跑 §6 校验流程，grep 新值是否在所有 5 主题下的边界用例都正常。

### 4.5.10 ❌ 整文件声明"主题豁免"但里面有些项不该豁免

**正确做法**：豁免注释**逐项列清楚**（不要写"等"或"全部"）。每个豁免项必须单独有"为什么"的业务理由。

### 4.5.11 ❌ "看起来颜色不对"先改 token 而不是先查树

**正确做法**：颜色不对先按 [[architecture]] §6.4 的调试步骤排查（嵌套 MaterialApp？Provider 树隔离？token 注入？组件裸 hex？），**90% 的"颜色不对"是树问题，不是 token 问题**。

### 4.5.12 ❌ "颜色太深"先想到 `surfaceContainerHighest` → `primaryContainer` 就停

**正确做法**：用 `Color.lerp(theme.colorScheme.surface, theme.colorScheme.primaryContainer, 0.2)` —— 80% surface + 20% primaryContainer。

### 4.5.13 用户实操边界白名单 — 这些场景**不算** §0.1 违规

> **本条来自 2026-08 审 calendar/AI 对话框的实战沉淀**。§0.1 原话是"输入 / 上传 / 选择"，但**用户实操卡得比原话更严**——只在真正承载"输入/表单选择"功能时才视为违规。下表是兜底判定清单。

#### 不算违规的具体场景

| 场景 | 典型写法 | 为什么不算 |
|---|---|---|
| **操作按钮**（含确认 / 删除）| `OutlinedButton(bg: pp.bgElevated)`、`FilledButton(bg: scheme.error)` 清空确认 | 按钮是动作触发，不是输入 |
| **头像 (CircleAvatar)**，包括半径较大的空状态 40dp | `CircleAvatar(radius: 16~40, bg: secondaryContainer)` | 视觉装饰元素 |
| **纯展示卡 / borderEmphasis 标记卡** | Container + border + accent 文本，强调当前选中 | 仅作视觉强调 |
| **Chat message bubble** | 圆角色块气泡样式 | 消息展示容器 |
| **Loading 状态指示** | `surfaceContainerHighest` loading bar / status indicator | §0.1 已明示的例外 |
| **LinearProgressIndicator 槽** | `LinearProgress.backgroundColor: surfaceContainerHighest` | 进度条槽底色 |
| **M3 标准 outline input** | TextField `border: OutlineInputBorder()` 无 `fillColor` | M3 标准 outline 不填充，OK |
| **页面 / Scaffold 全屏背景是深底 onSurface** | `Scaffold(backgroundColor: onSurface)` + AppBar 透明 | 反白夜间阅读的有意设计 |
| **占位 / 加载骨架** | `Container(color: surfaceContainerHighest) + CircularProgressIndicator` | 占位显示型 |

#### 严格违规判定流（按用户实操）

```
1. 是大色块卡片？（padding ≥ 16dp 或占满视口宽度）
   ├─ 否 → 不算违规
   └─ 是 ↓

2. 承载"输入 / 表单选择" 功能？
   ├─ 否 → 不算违规
   └─ 是 ↓

3. 是 TextField.fillColor / 表单选择控件 / 表单 sheet 大色块容器？
   ├─ 是 → ❌ 违规，改 Color.lerp(surface, primaryContainer, 0.2)
   └─ 否 → 重判
```

### 4.5.14 ❌ 识别色业务强行接 scheme 派生（v6.2 tetris 真实踩坑）

**症状**：tetris 棋盘切主题时方块颜色全错（I 变琥珀、O 变紫色、...），L 块（type 7）越界直接消失。

**根因**：`pieceColors` 改 `List<Color>` 0..6 强行从 scheme 派生，但 engine / Lua 协议始终用 1..7 → off-by-one + 越界。

**正确做法**：见 [[special-cases]] §1。识别色业务必须 native const + `Map<int, Color>` 1..7 索引。

**踩坑案例**：`fix(tetris): revert palette to native + fix pieceColors off-by-one`（commit 24d91ea1）。

## 5. 豁免规则（何时允许裸 hex）

允许 `Color(0xFF...)` 的只有两类，且**必须带 `主题豁免` 注释**说明业务理由：

1. **国际 / 品牌识别色**：斗兽棋暖米盘、Othello 绿盘黑白子、2048 原版识别色、小说书封面品牌渐变…
2. **数据持久化 / 业务必显色**：医学解剖标准色（骨蓝/肌红/关黄/器绿）、莫兰迪课程色（light 专属）、pigment 调色板本体、web_bookmark 站点色…
3. **特例 strategy（无需豁免注释，架构决策保留）**：
   - `tokens/color/tetris/tetris.dart` 4 角色 + 7 方块色（识别色锁定，玩家靠颜色识别方块）
   - `tokens/color/team/team.dart` 6 头像色（识别色锁定）
   - `lib/core/surround_game` 与 `lib/core/reversi` 的 `BoardThemeData`（86 处，见 [[architecture]] §5.8）

**红线**：`lib/` 新增代码不默认这些豁免——只有上面场景适用，任何其它裸 hex 都要先想通道。

## 6. 校验清单（动完必跑）

```bash
flutter analyze --no-pub        # 0 error
flutter build apk --debug        # √ Built
```

- 切到 zen / purple / ink / rose / lemon 五主题各审关键页一次（壳层、卡片、board 棋盘、game 色板）。
- **特例页面**（tetris / team_card）跨主题审一次：切主题后该不动的角色必须不变。
- 新增枚举 / 扩角色后，确认无遗漏 switch 分支（`getThemeData` / `materialThemeModeProvider` / displayName / icon）。
- strategy 扩展后跑一次测试或至少 analyze，确认 `==`/`hashCode` 改动不崩。
- 回到 [[color-usage-audit]] 更新：目录计数、迁移历史、Top 热点（如有变化）。
