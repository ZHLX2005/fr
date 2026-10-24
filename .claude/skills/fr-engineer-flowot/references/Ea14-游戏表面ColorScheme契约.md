---
name: game-surface-colorscheme-contract
description: 什么时候改游戏中心 / 房间就绪 / 大厅入口的配色时读——游戏表面只用 ColorScheme 角色的契约、各消费通道的现状（含无入口的 torchProtect）。
---

# Ea14 · 游戏表面 ColorScheme 契约

> 何时读：改游戏中心 / 房间就绪 / 大厅入口，且要跟 `AppThemeMode`（zen/purple/ink/rose/lemon/cobalt/dark 七主题）切换；或对照 `docs/prototypes/game-surfaces-palettes.html`。
>
> **通用消费通道**：普通/棋盘/象棋/俄罗斯方块/团队头像走 `context.colors / boardColors / chessColors / tetrisColors / teamAvatar`；数独走 `context.sudokuColors`（`lib/core/theme/context/sudoku_colors.dart`，注意其 ThemeExtension 尚未注入 app_theme，读数走 factory fallback）。
>
> **护眼通道当前无 context 入口**：`TorchProtectColorStrategyExtension` 已在 `lib/core/theme/app_theme.dart:156` 注册进 ThemeData，但 `lib/core/theme/context/` 下**没有** torch 扩展文件（只有 board/chess/colors/sudoku/team_avatar/tetris 六个），`grep -rn "get torchProtect" lib/` **0 命中**。所以 `context.torchProtect` 现在**不可用**——要读护眼策略得走 `Theme.of(context).extension<TorchProtectColorStrategyExtension>()`，或先补一个 context 扩展。
>
> 色值真相：`lib/design_tokens/color/palettes/{zen,purple,ink,rose,lemon,cobalt,dark}.dart`。主题机制见 [[Eb01-主题系统简述]]。

## 一、实现思路

### 必须 / 禁止

| 必须 | 禁止 |
| --- | --- |
| 铬件颜色只来自 `Theme.of(context).colorScheme` / `context.colors` | 在游戏表面硬编码 sage `#7A9A7E` / clay `#A0594A` |
| CTA 文字用 `onPrimary` / `onTertiary` | 假定 `onPrimary == white`（lemon/purple 为深色字） |
| 收藏 / 警告点缀走 `tertiary` | 把 lemon 的绿味 tertiary 当主 CTA 底 |
| 封面渐变用主题 cover token 或 slug 识别色表 | 全主题共用一套写死的深绿封面 |

### 角色速查（与原型 CSS 变量对齐）

| 用途 | Scheme |
| --- | --- |
| 主按钮底 | `primary` |
| 主按钮字 | `onPrimary` |
| 图标瓦 / chip.on 底 | `primaryContainer` |
| 图标瓦字 | `onPrimaryContainer` |
| 收藏、就绪描边、稀有强调 | `tertiary` / `onTertiary` |
| 卡面 | `surface` |
| 托盘 / 凹陷井 | `surfaceContainerHighest` |
| 弱字 | `onSurfaceVariant` |
| 分割 | `outline` |

### 三块表面同一契约

原型把同一套变量套在：

1. **游戏中心** — featured + 网格封面（布局见 [[Ea06-商店式内容页]]）  
2. **房间就绪** — code pill / seats / stacked CTA（[[Ea11-大厅与房间就绪]]）  
3. **大厅入口** — mark + form + 胶囊 CTA  

换 `data-palette` / `AppThemeMode` 只换 scheme，**不换布局几何**。

### 自检清单（改完必过）

- [ ] 切 purple/lemon 后主按钮字仍可读（用了 onPrimary）  
- [ ] 无 `Color(0xFF…)` 出现在本次改动的游戏 UI（豁免须注释）  
- [ ] fav 不是 primary 实心大块  
- [ ] Zen 默认观感仍对，但不依赖写死 Zen hex  

## 二、踩坑总结

| 坑 | 后果 | 正确做法 |
| --- | --- | --- |
| 从 Zen 原型抄 hex 进 Dart | 切主题失效 / 审计不过 | 只抄「用了哪个角色」 |
| 徽章/eyebrow 用 onPrimary 却铺在 surface | 对比度错 | 分清底角色再选 on* |
| 商店封面不跟主题 | purple 夜间仍是茶禅绿坡 | cover 梯度随 palette 或 slug×scheme 调 |

## 关联

- 路由 → [[Ea13-原型对齐路由]]
- 商店布局 → [[Ea06-商店式内容页]]
- 配色架构 → [[Eb01-主题系统简述]]
