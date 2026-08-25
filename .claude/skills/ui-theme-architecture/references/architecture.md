# 子 ref A：全局架构 + 数据流向（theme-architecture）

> 从 [SKILL.md](../SKILL.md) 导航进入。本文讲 **系统怎么分层、每个文件干什么、一次主题切换的数据如何流动**。
> 已知问题 / 配色速查 / 迁移历史见 [[color-usage-audit]]；动手改代码 SOP 见 [[extension]]。

## 0. 设计主线（一句话）

**「主色不动 · 环境染互补色温」** — v6.1 起，所有颜色统一从 `ColorScheme` 派生（组件层单数据源），
每个主题 = 主色族（原色不变）+ 环境族（按互补 hue 150°~170° 重新染色）+ 互补强调族（tertiary）+ 固定的 error 红系。

五个范本：
- **zen（茶禅，light）**：sage 绿（hue128°）漂在暖米环境（hue42°）
- **purple（暮紫，dark）**：暮紫主色（hue275°）漂在鎏金暖黑环境（hue45°）
- **ink（墨白，light）**：墨黑主色 + 纯纸白底 + 墨赭（hue18°）互补 + 章印朱红 error
- **rose（粉雾海盐，light）**：Velvet Bloom 粉主色（hue353°）+ 海盐薄荷互补（tertiary hue173°）+ 粉灰环境
- **lemon（柠檬鼠尾草，light）**：橄榄绿主色（hue61°）+ 柠檬黄强调（hue43°）+ 鼠尾草绿主背景

## 1. 分层总览

```
┌────────────────────────────────────────────────────────────────┐
│ Layer 1  tokens/   原料：跨主题中性色与几何 token（不感知主题）  │
│ Layer 2  semantic/ 语义：ColorScheme + AppColorsExtension 调色板 │
│ Layer 2.5 strategy/ 策略：ColorStrategy 抽象契约 + 默认实现      │
│ Layer 3  component/ 组件：复合组件样式主题                       │
│ 组装    app_theme.dart + theme_provider.dart → ThemeData + state │
│ 注入    extensions/* → 3 个 ThemeExtension 挂到 ThemeData        │
│ 消费    widgets/context_*  → context.colors / boardColors /      │
│         gameColors；Theme.of(...).colorScheme / extension<>()   │
└────────────────────────────────────────────────────────────────┘
```

依赖方向**严格自上而下**：`tokens → semantic → strategy → component → 组装 → 注入 → 消费`。
低层不 import 高层；semantic 只引用 tokens 的 RawColors；strategy 只依赖第 2 层的 scheme。

## 2. 文件地图

| 层 | 路径 | 关键符号 | 职责 |
| --- | --- | --- | --- |
| L1 | `lib/core/theme/tokens/colors.dart` | `RawColors` | 跨主题中性骨架：pureWhite / nearBlack / deepBlack / 9 档 neutral 灰阶 / 3 档 shadow alpha ® |
| L1 | `lib/core/theme/tokens/`（typography/spacing/radius/elevation） | — | 排版 / 间距 / 圆角 / 阴影几何 token |
| L2 | `lib/core/theme/semantic/colors.dart` | `ThemeColorSchemes` | **zen / purple / ink / rose / lemon 五套 `ColorScheme` 调色板**（每主题按色温互补染好） |
| L2 | `lib/core/theme/semantic/extensions.dart` | `AppColorsExtension` + `ThemeAppColors` | 状态色（success/warning/info/error）+ 分类色板（8 色），各主题一整套 |
| L2 | `lib/core/theme/semantic/typography.dart` | `AppTextThemes` | 文字排版（按 `scheme.brightness` 构建） |
| L2.5 | `lib/core/theme/strategy/color_strategy.dart` | `ColorStrategy` | 抽象契约：**6 核心角色**（accent/surface/outline/text/textMuted/danger）+ scheme 兜底；`@immutable` + `==`/`hashCode` |
| L2.5 | `lib/core/theme/strategy/default_color_strategy.dart` | `DefaultColorStrategy` | 完全从 scheme 派生 + **单例缓存**（`DefaultColorStrategy.of(scheme)`） |
| L2.5 | `lib/core/theme/strategy/board_color_strategy.dart` | `BoardColorStrategy` | 棋局契约：**11 棋盘角色**（background/gridLine/axisLabel/player1Stone/player2Stone/hint/winHighlight/lastMove/errorMark/neutral） |
| L2.5 | `lib/core/theme/strategy/default_board_color_strategy.dart` | `DefaultBoardColorStrategy` | 棋盘角色从 scheme 派生 + 单例缓存 |
| L2.5 | `lib/core/theme/strategy/game_colors_strategy.dart` | `GameColorsStrategy` | 游戏色板：7 方块 / 6 头像 / 五子棋黑白子 / 10 护眼色预设 |
| L2.5 | `lib/core/theme/strategy/default_game_colors_strategy.dart` | `DefaultGameColorsStrategy` | 方块/头像用 `Color.lerp(primary↔tertiary)` 派生（跨主题可读 + 主题辨识） |
| L2.5 | `lib/core/theme/strategy/theme_strategy_factory.dart` | `ThemeStrategyFactory.create(scheme)` | 编译期安全工厂（switch 表达式），当前所有主题统一走 `DefaultColorStrategy` |
| L3 | `lib/core/theme/extensions/*` | `ColorStrategyExtension` / `BoardColorStrategyExtension` / `GameColorsStrategyExtension` | ThemeExtension 注入器：**只存 strategy 实例，lerp 用 50% 阈值离散切换** |
| L3 | `lib/core/theme/component/`（button/card/input/section） | `AppButtonThemes` 等 | 复合组件样式（内置 componentTheme 已在 ThemeData 注册，此处只补非内置） |
| 组装 | `lib/core/theme/app_theme.dart` | `AppTheme.getThemeData(mode)` | switch 映射 mode → scheme + ext + cardShadow，`_buildTheme` 组装 ThemeData + 组件覆盖 |
| 状态 | `lib/core/theme/theme_provider.dart` | `ThemeNotifier` / `themeNotifierProvider` / `themeDataProvider` / `materialThemeModeProvider` | Riverpod 状态单一源；`hydrate()` 启动前加载，`setMode()` 落盘 SharedPreferences |
| 消费 | `lib/widgets/context_colors.dart` | `ColorStrategyContext` | `context.colors` → 6 核心角色（三层兜底） |
| 消费 | `lib/widgets/context_board_colors.dart` | `BoardColorContext` | `context.boardColors` → 11 棋盘角色 |
| 消费 | `lib/widgets/context_game_colors.dart` | `GameColorContext` | `context.gameColors` → 游戏色板 |
| Zen | `lib/widgets/theme/zen_theme.dart` | `ZenText` / `zenCardTheme` / `zenButtonTheme` / `ZenSection`… / `zenPageScaffold` | Zen 家族组件：委托 `Base*` + 锁定 `DefaultColorStrategy`；`ZenText` 保持 const |

## 3. 数据流向（一次主题切换的完整链路）

```
① 定义层（编译期常量，无运行时）
   ThemeColorSchemes.zen · ThemeAppColors.zen
            │ getThemeData(AppThemeMode.zen)
② 工厂组装 app_theme.dart
   ThemeStrategyFactory.create(scheme) → DefaultColorStrategy.of(scheme)  ← 单例缓存
   DefaultBoardColorStrategy.of(scheme) · DefaultGameColorsStrategy.of(scheme)
   _buildTheme(scheme, ext, cardShadow)
   → ThemeData(colorScheme, textTheme, extensions:[AppColorsExtension,
       ColorStrategyExtension, BoardColorStrategyExtension,
       GameColorsStrategyExtension], 组件主题覆盖…)
            │ themeDataProvider ref.watch(themeNotifierProvider)
③ 状态 theme_provider.dart
   ThemeNotifier.state = AppThemeMode        ← main() 前 hydrate() 注入持久值
   setMode() → state 更新 → themeDataProvider 重建 → MaterialApp 换 ThemeData
            │ MaterialApp(theme: ref.watch(themeDataProvider))
④ 注入 ThemeData.extensions
   Theme.of(context).extension<ColorStrategyExtension>() 读回 ColorStrategy
            │ 兜底：extension 为 null → DefaultColorStrategy.of(scheme)（绝不崩溃）
⑤ 消费 组件读颜色
   context.colors.accent / .textMuted …                    （6 角色）
   context.colors.scheme.primaryContainer …                 （scheme 兜底）
   context.boardColors.player1Stone / .winHighlight …       （棋盘）
   context.gameColors.pieceColors / .protectPresets …       （游戏）
   Theme.of(context).colorScheme.error …                    （M3 标准）
   Theme.of(context).extension<AppColorsExtension>().category …（分类/状态）
```

**时序要点**：切主题 → Notifier state 变化 → 派生 Provider 重建 ThemeData → `MaterialApp` 换新 Theme → 全树 `Theme.of` 读新 scheme → `context.colors` 返回新策略实例 → 依赖它的 widget rebuild。策略切换是**离散事件**：`ColorStrategyExtension.lerp` 用 `t < 0.5 ? this : other`，**不做跨色插值**（注释明确说明避免渐变鬼影）。

## 4. 三条消费通道怎么选

| 通道 | 读取方式 | 覆盖角色 | 典型使用者 |
| --- | --- | --- | --- |
| `context.colors` | `ColorStrategyExtension` | 6 核心 + scheme 兜底 | 页面 / 卡片 / 对话框 / 列表等一般 UI |
| `context.boardColors` | `BoardColorStrategyExtension` | 11 棋盘角色 | gomoku / tetris 棋盘（棋子黑白关系 + 棋盘环境独立） |
| `context.gameColors` | `GameColorsStrategyExtension` | 方块 / 头像 / 护眼 / 黑白子 | tetris 7 方块、team_card 6 头像、五子棋、torch 护眼灯 |
| `Theme.of(...).colorScheme.X` | M3 标准 | primary/secondary/tertiary/surface/error… | 跨主题一致性要求高的壳层、需要 M3 角色的地方 |
| `AppColorsExtension` | `Theme.of(...).extension<>()` | success/warning/info/error + category(8) | 图表 / 标签分类 / 优先级等色彩多样性场景 |

> 决策速查（哪类目录用哪条）在 [[color-usage-audit]] §6。

## 5. 关键设计决策（改代码前必读）

1. **单例缓存**：`DefaultColorStrategy.of(scheme)` 只在 scheme 不同时重建实例——避免 `ColorStrategy` 作为 ThemeExtension 被反复 new 导致的 GC 抖动。**所有策略类唯一入口是各自的 `.of(scheme)` 工厂。**
2. **`==` / `hashCode` 已按角色重写**：相同方案复用实例 → Flutter 识别相同策略 → 避免不必要 rebuild。
3. **ThemeExtension 只存实例不存 BuildContext**（防止内存泄漏）；`lerp` 强制返回 `this` 或 `other` 而非 `Color.lerp` 插值。
4. **三层兜底**：`context.colors` = extension 命中 → 否则 `DefaultColorStrategy.of(scheme)`，**绝不返回 null / 绝不崩溃**。
5. **compile-time factory**：`ThemeStrategyFactory.create` 用 switch 表达式杜绝运行时 KeyError；v7 简化为所有主题统一 `DefaultColorStrategy`（无特例策略）。
6. **`SURFACE` 与 `TEAM` 角色重叠靠独立通道解决**：`scheme.surface` 同时是页面卡片底又是棋盘底 → 棋盘单独走 `boardColors`；胜方高亮需要跳出主题 → `winHighlight = scheme.tertiary`（互补色）。
7. **保留的硬编码豁免**（属设计决策）：`lib/core/surround_game` 与 `lib/core/reversi` 用各自 `BoardThemeData` 令牌（86 处 hex，warm/cool 两套预设，30+ 角色），与 `context.boardColors` 平级，v7 议题记录为"保持现状"。

## 6. 与 Zen 家族组件的关系

`zen_theme.dart` 是 **Zen 家族的视觉识别层**，与通用主题系统并存：
- `ZenText`：const 排版，`color` 字段**硬编码暖墨色**（家族识别的一部分），要跟主题用 `.copyWith(color: scheme.X)` 覆盖。
- `zenCardTheme` / `zenDottedZoneTheme` / `zenButtonTheme`：v6 Heritage 版，内部读 `DefaultColorStrategy.of(scheme)`（**不是** `context.colors`），保证 zen 组件在非 zen 主题下仍抓取当前 scheme 的 surface/outline。
- `ZenSection` / `ZenIconButton` / `ZenDot` 等：委托 `widgets/base/*` 组件 + 锁定 `DefaultColorStrategy`。
- `zenPageScaffold`：保留的兼容壳（23 个 consumer），读 `scheme.surfaceContainerHighest`。
- 已删除（v6.2 收尾）：`ZenColors` 类、`zenCard()` / `zenDottedZone()` / `zenButton()` 三个 deprecated 兼容函数。