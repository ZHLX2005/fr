---
name: Eb06-token变量定义
description: FR 设计 token 的数值字典——圆角/间距/字体档位、7 套主题色板、ColorStrategy 与各域 strategy 的角色清单、消费入口对照。写 UI 取 token 数值、评审「这个值该不该进 token」时读；系统架构见 Eb01。
---

# Eb06 — token 变量定义

> 适用范围：仅 FR 项目。本文件是 **token 字典**：每类 token 的定义位置、全部档位/角色、消费入口。数值以当前源码为准（本文基线 2026-10-24）；扩展角色/主题的 SOP 见 [[Eb03-扩展SOP与迁移]]，系统分层见 [[Eb01-主题系统简述]]。
> token 分层：本文件 §1–§2 是 **Layer 1**（`lib/design_tokens/`，纯常量不依赖 BuildContext）；§3 的 strategy 角色属 **Layer 2/3**（`lib/core/theme/`）；层级依赖方向见 [[Ec01-组件分层与复用契约]] §1。

## 1. 几何 token（`lib/design_tokens/`）

### 1.1 圆角 `AppRadius`（`radius.dart`）

| 档位 | 值 | 语义 |
|---|---:|---|
| `AppRadius.xs` | 4 | Tag / 小型按钮 |
| `AppRadius.sm` | 6 | zen 卡片 |
| `AppRadius.md` | 8 | 输入框 / 列表项 |
| `AppRadius.lg` | 12 | 按钮 |
| `AppRadius.xl` | 16 | 卡片（Material 3 标准） |
| `AppRadius.xxl` | 24 | Hero 大卡 / 顶部 hero 区 |

`AppBorderRadius.allXs … allXxl`：预构 `BorderRadius`，省 widget 端重复构造。

**已知错位**：代码里实际还散落 10 / 11 / 14 / 18 / 20 / 22 / 28 等档位外数值（Ea08–Ea11 的配方尤其多）。规则：新代码只取上述 6 档；确需档位外值 → 先在 Eb01/Eb03 层面裁决是否扩档，不得私加。

### 1.2 间距 `AppSpacing`（`spacing.dart`）

| 档位 | 值 | 语义 |
|---|---:|---|
| `AppSpacing.xxs` | 4 | 紧凑连接（icon 与文字间隙） |
| `AppSpacing.xs` | 8 | 组件内部紧凑间距 |
| `AppSpacing.sm` | 12 | 列表项内边距 |
| `AppSpacing.md` | 16 | 卡片内边距基线 |
| `AppSpacing.lg` | 24 | 页面内边距 / 大块间距 |
| `AppSpacing.xl` | 32 | 段落间距 |
| `AppSpacing.xxl` | 48 | 顶部留白 |

> 边界：组件层（core/ui/、zen/、app_theme）的 padding/margin/SizedBox 从这里取；**业务页面的一次性排版值不强制迁移**（spacing.dart 头注原文）。

## 2. 字体 token（`lib/design_tokens/typography.dart`）

| token | 值/形态 | 用途 |
|---|---|---|
| `AppFontFamily.sans` | `'sans-serif'` | 主字体族 |
| `AppFontFamily.sansFallback` | `-apple-system / BlinkMacSystemFont / Segoe UI / Roboto / Helvetica Neue / …` | 走 `fontFamilyFallback` 保证跨平台 |
| `AppFontFamily.mono` | `'monospace'` | 等宽（数字/时钟），配 tabularFigures |
| `AppFontFamily.monoFallback` | 列表 | 同上回退 |
| `AppFontWeight.thin/light/…` | `FontWeight.w200/w300/…` | 字重档位 |

语义层（什么场景用什么字）不在 L1：`lib/core/theme/text_theme.dart`（Layer 3，semantic TextTheme）。

## 3. 颜色 token（`lib/design_tokens/color/` + `lib/core/theme/colors/`）

### 3.1 主题色板（7 套，一套 mode 一个文件）

`lib/design_tokens/color/palettes/{purple, zen, ink, rose, lemon, cobalt, dark}.dart`，与 `AppThemeMode` 七值一一对应（对照表见 [[Eb01-主题系统简述]] §1）。

### 3.2 Material ColorScheme（M3 原生）

入口 `Theme.of(context).colorScheme`；primary / onPrimary / primaryContainer / onPrimaryContainer / surface / onSurface / surfaceContainerLowest…error 等 M3 全套角色。**页面前景/底色默认先取这里**。

### 3.3 `AppColorsExtension`（应用语义色，12 角色）

`lib/design_tokens/color/app_colors_extension.dart:14-25`：

- `success` / `onSuccess` / `successContainer` / `onSuccessContainer`
- `warning` / `onWarning` / `warningContainer` / `onWarningContainer`
- `info` / `onInfo` / `infoContainer` / `onInfoContainer`

按主题注入（`lib/core/theme/app_theme.dart:90-92`）。**暂无 context 访问器**（`lib/core/theme/context/` 缺 `app_colors.dart`）——当前唯一重度消费方是 `lib/core/ui/global/notification/main.dart`（其 33 处 hex 的根因，见 [[Ec02-组件现状与收敛路线]] 待办）。

### 3.4 `ColorStrategy`（应用语义角色，6 个）

契约 `lib/core/theme/colors/strategy/color_strategy/color_strategy.dart:15-30`：

`accent` · `surface` · `outline` · `text` · `textMuted` · `danger`

入口 `context.colors`（`lib/core/theme/context/colors.dart`，ThemeExtension 三层兜底）；默认实现 `DefaultColorStrategy.of(colorScheme)`。

### 3.5 域内 strategy（游戏/专属色，识别色锁定或 scheme 派生）

| 域 | 契约/角色位置 | 入口 | 规模 |
|---|---|---|---|
| 棋盘 | `lib/core/theme/colors/strategy/board_color_strategy/` | `context.boardColors` | 11 角色 |
| 国际象棋 | `…/chess_color_strategy/` | `context.chessColors` | 13 角色（棋子图走 asset，不消费 stone 角色） |
| 数独 | `…/sudoku_color_strategy/` | `context.sudokuColors` | 8 角色 + cellBg/cellText 子结构；**extension 尚未在 app_theme 注入，context 走 factory fallback** |
| 俄罗斯方块 | `lib/design_tokens/color/tetris.dart` | `context.tetrisColors` | 3 角色 + 7 方块色 Map（`0xFF2AD4E0` candy cyan 等，跨主题锁定） |
| 团队头像 | `…/team_avatar_color_strategy/` | `context.teamAvatar` | 6 头像色（锁定） |
| 护眼 | `…/torch_protect_color_strategy/` | **无 context 入口** | 4 角色（protectWarmYellow / protectWarmOrange / protectNeutral / protectCoolWhite） |

角色名以各 `*_color_strategy.dart` 源文件为准；精确 hex 值只在 `lib/design_tokens/color/` 定义（单一事实源）。

## 4. 消费判定（这个颜色走哪个入口）

```text
是 Material 语义（primary/error/…）？        → Theme.of(context).colorScheme
是应用六角色（文字/弱文字/描边/面底/强调/危险）？ → context.colors
是成功/警告/信息？                            → 暂无 context 入口（现有代码：AppNotification 豁免；新增请先补 app_colors.dart）
是棋类/专属域色？                             → context.<域>Colors
是跨主题必须固定的识别色？                     → 按 [[Eb05-颜色特例策略]] 登记，不进 strategy
都不是（纯装饰一次性值）？                     → 复查是否真的需要；仍要则集中登记在 const 文件，禁止散落
```

**几何/字体同理**：圆角/间距只取 §1 两表档位；字号走 semantic TextTheme，不在 widget 里写死 fontSize 之外再发明新档。

## 5. 「这个值要不要进 token」

- 同类值出现 **≥3 处**且语义相同（如统一的列表项内边距）→ 进 token 或组件默认参数。
- 一次性排版值 → 不强制（见 §1.2 边界）。
- 颜色永不裸写 hex 进 widget；识别色例外按 Eb05 走登记。
- 新增档位/角色一律走 [[Eb03-扩展SOP与迁移]]，并在本文件登记一行。

## 6. 与其它 ref 的分工

| 诉求 | 去哪 |
|---|---|
| 系统分层/数据流/通道选择 | [[Eb01-主题系统简述]] |
| 新增主题/角色/迁移 SOP | [[Eb03-扩展SOP与迁移]] |
| 用色规模与残留审计 | [[Eb04-颜色用量审计]] |
| 固定识别色豁免 | [[Eb05-颜色特例策略]] |
| 组件放哪层 | [[Ec01-组件分层与复用契约]] / [[Ec03-组件内聚位置]] |
