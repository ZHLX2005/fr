# 子 ref B：如何扩展（theme-extension）

> 从 [SKILL.md](../SKILL.md) 导航进入。本文给 **主题系统的扩展与迁移 SOP**：新增配色、新增语义角色、新增组件样式、把既有硬编码迁到主题通道、豁免判定。
> 系统分层/文件地图先看 [[architecture]]；用量现状/热点文件看 [[color-usage-audit]]。

## 0. 扩展动作速查表

| 我想… | 动哪些文件 | 详见 |
| --- | --- | --- |
| 新增一套主题配色 | `semantic/colors.dart` + `semantic/extensions.dart` + `app_theme.dart`（+可选 `materialThemeModeProvider`） | §1 |
| 新增强调色 / 语义角色（如 danger→warning、新增 focus 色） | `strategy/color_strategy.dart` + `strategy/default_color_strategy.dart`（+ 其他策略如有同类需求） | §2 |
| 新增 / 改一个复用的组件样式 | `component/` 或 `zen_theme.dart` helper | §3 |
| 把既有硬编码色迁到主题通道 | 迁移 SOP | §4 |
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



## 1. 新增一套主题配色

**数据入口三件套必须同步**（缺一不可，否则 `getThemeData` 会缺参）：

1. **`semantic/colors.dart` → `ThemeColorSchemes`**：新增 `static const ColorScheme foxy = ColorScheme(...)`。
   - 按「主色族不动 + 环境族染互补 hue（差 150°~170°）+ tertiary 互补强副 + error 保持」设计。
   - onPrimary/onError 等纯黑纯白引用 `RawColors`；环境色注意与主色 hue 对比度。
2. **`semantic/extensions.dart` → `ThemeAppColors`**：新增对应 `AppColorsExtension`。
   - 状态色（success/warning/info + 容器族）+ `category` 8 色，跨「主色族 / 环境族 / 互补族」混排。
   - info 建议用 tertiary 互补色族呼应主色。
3. **`app_theme.dart`**：
   - `enum AppThemeMode` 加一个枚举值。
   - `getThemeDisplayName` / `getThemeIcon` 的 switch 各补一支。
   - `getThemeData` 的 switch 加 `_buildTheme(scheme:..., ext:..., cardShadow:...)`（cardShadow 深色主题用 `RawColors.shadowMedium/shadowHeavy`，浅色用 `shadowLight`）。
4. **`theme_provider.dart`**：若新主题是深色（`Brightness.dark`），`materialThemeModeProvider` 的 switch 要补 `AppThemeMode.foxy => ThemeMode.dark`，否则浅色主题全落 `_ => light` 分支。

校验：切到新主题整页审一遍（重点：卡片/对话框 surface 对比、正文 onSurface、边框 outline、危险 error）。

## 2. 扩展语义角色（ColorStrategy）

> 只在该角色**跨页面复用且语义清晰**时才加；角色过多会让 `==`/`hashCode` 和所有实现都变重。默认策略已覆盖 6 核心 + scheme 兜底，多数新需求用 `context.colors.scheme.X` 或 `AppColorsExtension` 就够。

若确需新增（示例：增加 `info` 角色）：

1. `strategy/color_strategy.dart`：抽象加 `Color get info;`，并在 `==`/`hashCode` 中并入 `info`。
2. `strategy/default_color_strategy.dart`：实现 `info => scheme.tertiary`（或选合适 scheme 角色映射）。
3. 如还有 board/game 策略需要相同角色，照 `default_board_color_strategy.dart` / `default_game_colors_strategy.dart` 同法扩，并同步它们的 `==`/`hashCode`。
4. 消费端已有 `context.colors` 快捷入口，扩接口后自动可用，无需改 `context_colors.dart`。

> ⚠️ 任何实现 `ColorStrategy` 的类都要满足 `@immutable` + 角色全覆盖 + `==`/`hashCode` 一致性，否则策略去重与 rebuild 失效。

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
| 方块 / 头像 / 护眼 | `context.gameColors.X` | `pieceColors[i]`（i 固定即语义固定）/ `avatarColors` |
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
- AppBar → `colorScheme.surface`
- Scaffold → `colorScheme.surface`
- BottomNavigationBar → `colorScheme.surface`
- Card → 默认走 `CardTheme.color = scheme.surface`（`app_theme.dart` 已配好）

**踩坑案例**：`lib/widgets/theme/zen_theme.dart` `zenPageScaffold`、`lib/core/theme/app_theme.dart` `appBarTheme`/`bottomNavigationBarTheme` 之前用 `surfaceContainerHighest`，改 `surface` 后整页变通透。

### 4.5.2 ❌ 用 `inversePrimary` 当 AppBar / Scaffold 背景

**症状**：AppBar 颜色与主色互补，整页色调诡异（深色主题下尤其突兀）。

**根因**：`inversePrimary` 是为"主题翻转"设计的强调色（亮/暗互补），不是基础背景。

**正确做法**：直接删掉 `backgroundColor:` 让它走 AppBarTheme 默认值（=`scheme.surface`）。要更深背景 → 用 `surfaceContainer`，不要用 `inversePrimary`。

**踩坑案例**：`lib/lab/demos/crash_log_demo.dart` / `kvcli_todo_demo.dart` / `overlay_demo.dart` / `schema_demo.dart` 的 AppBar 之前用 `inversePrimary`，移除后页面恢复正常。

### 4.5.3 ❌ 用 `surfaceVariant`（已 deprecated）

**症状**：analyze 报 `deprecated_member_use`，未来 Flutter 版本会编译失败。

**根因**：M3 把 `surfaceVariant` 拆成 5 档 `surfaceContainer*`，旧的 `surfaceVariant` 已废弃。

**正确做法**：换成 `surfaceContainerHighest`（语义最接近：弱化表面）。如果嫌深，再换成 `surface` 或 `surfaceContainerHigh`。

**踩坑案例**：`lib/lab/demos/web_bookmark_demo.dart` 多处用 `surfaceVariant`，改 `surfaceContainerHighest`。

### 4.5.4 ❌ 用 `Color.lerp(color, Colors.white/black, 0.5)` 调淡

**症状**：hover/selected 背景"看起来淡了但灰蒙蒙的"。

**根因**：用 `Colors.white/black` 中和会拉低饱和度，结果是灰色不是"淡主题色"。

**正确做法**：用主题角色：`primaryContainer` / `secondaryContainer` / `tertiaryContainer`（已是该主题的"浅色版本"）。要更淡 → `Color.lerp(surface, primaryContainer, 0.2)`（保留色调但接近纯白底）。

**踩坑案例**：web_bookmark 的 icon selector 之前 `selectedColor.withAlpha(51)`（淡灰），改 `primaryContainer`。

### 4.5.5 ❌ Card 背景用 `onSurface`（light 主题下变深底）

**症状**：卡片在 light 主题下背景变成深色，文字看不清楚。

**根因**：用 M3 角色记错——`onSurface` 是"表面**上**的文字色"，不是表面本身的色。在 light 主题下 onSurface 是深色（接近黑），把它当 card 背景就成黑底卡片。

**正确做法**：Card 背景用 `surface`。`onSurface` 只用于文字/图标前景色。

**踩坑案例**：`lib/lab/demos/web_bookmark_demo.dart` `_BookmarkCard` 之前 `backgroundColor: onSurface`（dark 主题下"碰巧"看起来合理，light 主题下就翻车）。

### 4.5.6 ❌ outline 调成太淡的纯灰

**症状**：次要图标 / 分割线 / 输入框边框几乎看不见，但边框本身又不够清晰。

**根因**：`outline` 这个角色**多重用途**——同时承担边框、分割线、次要图标、占位符色。调太淡（如 `#E6E6E6` 纯灰）会让"次要图标"和"分割线"看不见。

**正确做法**：保留**带主题色温的淡色调**——lemon 用淡柠檬白 `#EAE5D6`、rose 用淡粉白 `#EADEE1`。跨主题一致（不鲜艳），但保留了色调辨识度，且作为图标/分割线仍可见。

**踩坑案例**：`colors.dart` lemon/rose outline 从纯亮黄/纯粉 → 太深 → 最终定为带主题色温的淡色调（呼应主题设置色点的低调描边 `Colors.black12`）。

### 4.5.7 ❌ Icon container 背景用 `bookmark.color.withAlpha(51)`

**症状**：icon 背景半透明彩色，hover/selected 时颜色混乱。

**根因**：用业务数据色做背景 + 50% alpha —— 跨主题不可控（dark 主题下会变成深色）。

**正确做法**：icon container 背景用 `primaryContainer`（选中）或 `surfaceContainerHighest`（未选）；边框用 `primary`/`outline`。

**踩坑案例**：`lib/lab/demos/web_bookmark_demo.dart` 多处 icon container 改 `primaryContainer`。

### 4.5.8 ❌ Markdown code 块背景用 `surfaceContainerHighest`

**症状**：深色代码块在 light 主题下也偏深。

**正确做法**：用 `primaryContainer`（浅主题色块，代码对比度好）。注意 dark 主题下 `primaryContainer` 仍是浅色，需要验证可读性。

**踩坑案例**：`lib/widgets/markdown_renderer_widget.dart` code/codeblock 改 `primaryContainer`。

### 4.5.9 ❌ 修改 ColorScheme 后没核对引用面

**症状**：改了 `surface` 或 `outline` 后某些页面"颜色突然变了"，但不知道是预期还是 bug。

**正确做法**：改 ColorScheme 后跑 §6 校验流程，grep 新值是否在所有 5 主题下的边界用例都正常（如 dark 主题 surface 是否够深、light 主题 outline 是否够可见）。

**踩坑案例**：purple 主题 surface 之前被错误地改亮（#3A3832）→ 后续用户报告"暮紫背景不够深" → 改回 #201F1A。**所有 ColorScheme 改动必须有"为什么"的注释，否则下次又会被误改。**

### 4.5.10 ❌ 整文件声明"主题豁免"但里面有些项不该豁免

**症状**：文件顶部注释说"本文件所有 `Color(0xFF...)` 都是豁免"，但其中某一项其实是用户希望走主题的。

**正确做法**：豁免注释**逐项列清楚**（不要写"等"或"全部"）。每个豁免项必须单独有"为什么"的业务理由（品牌识别 / 数据固定 / 解剖标准色…）。用户后续要拿掉某个豁免项时只动那一处。

**踩坑案例**：`lib/core/novel_reader/novel_reader_page.dart` 顶部注释一开始说"烫金封面渐变 0xFFDFB982→0xFF6E3D27 也豁免"——后续用户要求**不豁免**书皮封面，改走主题三段渐变 `tertiaryContainer → primary → onPrimaryContainer`。注释同步更新为逐项豁免（只留纸张底色/棕色墨水）。

### 4.5.11 ❌ "看起来颜色不对"先改 token 而不是先查树

**症状**：发现某 demo 颜色错了，直接去改 `colors.dart` / `extensions.dart` / `DefaultColorStrategy`。改完一堆其它页面也跟着崩。

**正确做法**：颜色不对先按 [[architecture]] §7.3 的调试步骤排查（嵌套 MaterialApp？Provider 树隔离？token 注入？组件裸 hex？），**90% 的"颜色不对"是树问题，不是 token 问题**。

**踩坑案例**：暮紫主题 surface 之前被错误地"调亮"以适配"时钟卡片不走主题通道"——实际根因是 clock_demo 嵌套 MaterialApp 不继承 colorScheme（已单独修）。改 token 是治标错的。

### 4.5.12 ❌ "颜色太深"先想到 `surfaceContainerHighest` → `primaryContainer` 就停

**症状**：把"颜色太深"的卡片从 `surfaceContainerHighest` 换成 `primaryContainer`，用户反馈"还是太深"。

**根因**：`primaryContainer` 在 lemon（#FFF9C4）、rose（#FECBCB）等主题下虽然比 surfaceContainerHighest 浅，但仍**有可见饱和度**——卡片色块铺满时仍会"显色"。

**正确做法**：用 `Color.lerp(theme.colorScheme.surface, theme.colorScheme.primaryContainer, 0.2)` —— 80% surface + 20% primaryContainer。背景几乎看不出主题色调，仅在对比时才有微弱色感。

**踩坑案例**：notion_image_host 拍照框 + 文字输入框 → surfaceContainerHighest → primaryContainer → `Color.lerp(0.4)` → `Color.lerp(0.2)`。这才是"承载交互的大色块卡片该有的浅度"。



## 5. 豁免规则（何时允许裸 hex）

允许 `Color(0xFF...)` 的只有两类，且**必须带 `主题豁免` 注释**说明业务理由：

1. **国际 / 品牌识别色**：斗兽棋暖米盘、Othello 绿盘黑白子、2048 原版识别色、小说书封面品牌渐变…
2. **数据持久化 / 业务必显色**：医学解剖标准色（骨蓝/肌红/关黄/器绿）、莫兰迪课程色（light 专属）、pigment 调色板本体、web_bookmark 站点色…
3. **独立令牌系统（无需豁免注释，架构决策保留）**：`surround_game` / `reversi` 的 `BoardThemeData`（86 处，见 [[architecture]] §5.7）。

**红线**：`lib/` 新增代码不默认这些豁免——只有上面场景适用，任何其它裸 hex 都要先想通道。

## 6. 校验清单（动完必跑）

```bash
flutter analyze --no-pub        # 0 error
flutter build apk --debug        # √ Built
```

- 切到 zen / purple / ink / rose / lemon 五主题各审关键页一次（壳层、卡片、board 棋盘、game 色板）。
- 新增枚举 / 扩角色后，确认无遗漏 switch 分支（`getThemeData` / `materialThemeModeProvider` / displayName / icon）。
- strategy 扩展后跑一次测试或至少 analyze，确认 `==`/`hashCode` 改动不崩。
- 回到 [[color-usage-audit]] 更新：目录计数、迁移历史、Top 热点（如有变化）。