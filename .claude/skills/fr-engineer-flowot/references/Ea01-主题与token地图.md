---
name: Ea01-主题与token地图
description: FR 主题与颜色的一页地图——取色决策树、7 套主题、分层链路、各色通道清单、主题切换数据流、待补缺口清单。判断「这个颜色该走哪个通道」「这个 extension 为什么读不到」时读；token 数值见 Ea02。
---

# Ea01 — 主题与 token 地图

> 骨架层 · 主题与颜色。索引与红线见 [[E00-UI骨架地图]]，token 数值字典见《Ea02 token 字典》，视觉基调判据见《Ea03 视觉决策基线》。
> 具体主题名、角色数、实现路径以当前源码为准；本文数字滞后时先核实代码。

## 1. 取色决策树（先走这张）

```text
是 Material 语义（primary / error / surface…）？
    → Theme.of(context).colorScheme（M3 原生全套）

是应用六角色（主文字 / 弱文字 / 描边 / 面底 / 强调 / 危险）？
    → context.colors（ColorStrategy：accent surface outline text textMuted danger）

是成功 / 警告 / 信息（跨主题固定语义色）？
    → 当前无 context 入口（AppColorsExtension 12 角色）→ 见 §6 缺口清单

是棋类 / 专属域色？
    → context.boardColors / chessColors / sudokuColors / tetrisColors / teamAvatar

是跨主题必须固定的识别色（棋盘识别色等）？
    → 《Ec03 特例豁免》登记，不进 strategy

都不是（纯装饰一次性值）？
    → 复查是否真的需要；仍要则集中登记在 const 文件，禁止散落
```

> 几何/字体同理：圆角、间距只取《Ea02 token 字典》§1–§2 档位；字号走 semantic TextTheme。

## 2. 7 套主题

`AppThemeMode`（`lib/core/theme/colors/theme_mode.dart:7`）：

| mode | 名称 | 明暗 | 色向 |
|---|---|---|---|
| `purple` | 暮紫 | 深 | 暮紫主色 + 冷炭紫环境 + 稀用鎏金 |
| `zen` | 茶禅 | 浅 | sage 绿 + 暖米环境 + 陶土红强调 |
| `ink` | 墨白 | 浅 | 墨黑主色 + 暖生宣纸底 + 章印朱红 |
| `rose` | 粉雾 | 浅 | 近白页 + 尘玫瑰 CTA |
| `lemon` | 柠檬鼠尾草 | 浅 | 黄油主色 + 低彩鼠尾草 |
| `cobalt` | 宝蓝 | 浅 | 宝蓝 + 纯白高对比 |
| `dark` | 暗黑 | 深 | 暗底高对比 |

对应色板：`lib/design_tokens/color/palettes/{purple,zen,ink,rose,lemon,cobalt,dark}.dart`（一套 mode 一个文件）。

## 3. 分层链路

```text
design tokens / palettes            ← lib/design_tokens/（Layer 1，纯常量）
    → Theme / ColorScheme           ← lib/core/theme/app_theme.dart 装配
    → domain ColorStrategy          ← lib/core/theme/colors/strategy/（每域一个契约 + default 实现）
    → ThemeStrategyFactory + ThemeExtension ← factory.dart + lib/core/theme/extensions/
    → ThemeData 注入 MaterialApp
    → context.colors / boardColors / chessColors / sudokuColors / teamAvatar / tetrisColors
```

依赖方向自上而下：token 不依赖组件；组件不各自造调色板。策略缓存与默认构造走 `factory.dart` / `Default...Strategy.of(scheme)`，不绕过。

## 4. 通道清单

| 通道 | 入口 | 角色规模 | 备注 |
|---|---|---|---|
| Material ColorScheme | `Theme.of(context).colorScheme` | M3 全套 | 页面前景/底色默认先取这里 |
| 应用语义色 | `context.colors` | 6 | `accent surface outline text textMuted danger` |
| 棋盘 | `context.boardColors` | 11 | scheme 派生 |
| 国际象棋 | `context.chessColors` | 13 | 棋子图走 asset，不消费 stone 角色 |
| 数独 | `context.sudokuColors` | 8 + cellBg/cellText | extension 未注入，走 factory fallback（见 §6） |
| 俄罗斯方块 | `context.tetrisColors` | 3 + 7 方块色 Map | 方块色跨主题锁定 |
| 团队头像 | `context.teamAvatar` | 6 | 锁定 |
| 护眼 | **无 context 入口** | 4 | 见 §6 缺口清单 |
| 成功/警告/信息 | **无 context 入口** | 12 | AppColorsExtension，见 §6 缺口清单 |

## 5. 主题切换数据流

```text
用户选择 AppThemeMode
   ↓ themeNotifierProvider / ThemeNotifier 更新状态
   ↓ themeDataProvider 调用 AppTheme 组装 ThemeData
   ↓ ThemeStrategyFactory 从新 ColorScheme 创建各 domain strategy
   ↓ ThemeExtension 注入 MaterialApp 的 ThemeData
   ↓ widget 读取 context.*Colors 或 Theme.of(context).colorScheme
```

## 6. 缺口清单（可勾销：补一个删一行）

| 缺口 | 现状 | 补法 |
|---|---|---|
| `AppColorsExtension` 无 context 访问器 | 12 个语义角色（success/warning/info 各 on/container 四形态）已按主题注入 ThemeData（`lib/core/theme/app_theme.dart:90-92`），但 `lib/core/theme/context/` 无 `app_colors.dart` | 补 context 扩展；当前重度消费方是 `lib/core/ui/global/notification/main.dart`（其 33 处 hex 的根因） |
| `TorchProtectColorStrategyExtension` 无 context 入口 | 已在 `app_theme.dart:156` 注册，`lib/core/theme/context/` 只有 colors/board/chess/sudoku/team_avatar/tetris 六个文件；`grep -rn "get torchProtect" lib/` 0 命中 | 补 context 扩展；当前只能 `Theme.of(context).extension<TorchProtectColorStrategyExtension>()` |
| 数独 extension 未注入 app_theme | `context.sudokuColors` 走 factory fallback | 在 app_theme 注入后删除此行 |

> 引用 `context.torchProtect` / `context.appColors` 目前都是**不存在的 API**——写代码前先查本表。

## 7. 红线

- `lib/` 新增 UI 默认禁止裸写 `Color(0xFF…)`；先消费 ColorScheme 或项目 strategy。
- 只有业务语义要求颜色稳定、切主题会造成身份/规则误读时，才考虑固定识别色特例，按《Ec03 特例豁免》审核。
- Strategy/ThemeExtension 的创建和迁移遵循《Ec01 扩展SOP与迁移》，不在组件或页面内临时建立第二套主题机制。
