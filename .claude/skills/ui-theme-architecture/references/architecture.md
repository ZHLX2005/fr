# 子 ref A：全局架构 + 数据流向（theme-architecture）

> 从 [SKILL.md](../SKILL.md) 导航进入。本文讲 **系统怎么分层、每个文件干什么、一次主题切换的数据如何流动**。
> 已知问题 / 配色速查 / 迁移历史见 [[color-usage-audit]]；动手改代码 SOP 见 [[extension]]；tetris / teamAvatar 为何"不跟主题"见 [[special-cases]]。

## 0. 设计主线（一句话）

**「主色不动 · 环境染互补色温」** — v6.1 起，所有颜色统一从 `ColorScheme` 派生（组件层单数据源），
每个主题 = 主色族（原色不变）+ 环境族（按互补 hue 150°~170° 重新染色）+ 互补强调族（tertiary）+ 固定的 error 红系。
v6.2 把 strategy 层拆成 5 个独立 strategy（含 2 个"识别色锁定"特例），3 通道扩展为 5 通道。

五个范本：
- **zen（茶禅，light）**：sage 绿（hue128°）漂在暖米环境（hue42°）
- **purple（暮紫，dark）**：暮紫主色（hue275°）漂在鎏金暖黑环境（hue45°）
- **ink（墨白，light）**：墨黑主色 + 纯纸白底 + 墨赭（hue18°）互补 + 章印朱红 error
- **rose（粉雾海盐，light）**：Velvet Bloom 粉主色（hue353°）+ 海盐薄荷互补（tertiary hue173°）+ 粉灰环境
- **lemon（柠檬鼠尾草，light）**：橄榄绿主色（hue61°）+ 柠檬黄强调（hue43°）+ 鼠尾草绿主背景

## 1. 分层总览（v6.2）

```
┌────────────────────────────────────────────────────────────────┐
│ Layer 1  tokens/   原料：跨主题中性色 + 各用途色板（不感知主题） │
│   ├── raw/     中性骨架（pureWhite/nearBlack/灰阶/shadow）     │
│   ├── base/    跨主题锁定的功能色（识别色、护眼等）             │
│   ├── board/   棋盘专属 token                                   │
│   ├── team/    团队卡头像色                                     │
│   ├── tetris/  俄罗斯方块 7 方块色 + 棋盘环境（v6.2 特例）      │
│   ├── torch/   灯具护眼色                                       │
│   └── theme/   5 主题 ColorScheme + AppColorsExtension（独立目录）│
│ Layer 2  strategy/ 5 个 strategy 抽象契约 + 默认实现            │
│ Layer 2.5  color/ 5 策略统一工厂 + extensions/ ThemeExtension 注入│
│ Layer 3  component/ 组件：复合组件样式主题                       │
│ 组装    app_theme.dart + state/theme_provider.dart → ThemeData   │
│ 注入    extensions/* → 5 个 ThemeExtension 挂到 ThemeData        │
│ 消费    widgets/context_*  → context.colors / boardColors /      │
│         tetrisColors / teamAvatar / torchProtect                 │
└────────────────────────────────────────────────────────────────┘
```

依赖方向**严格自上而下**：`tokens → strategy → component → 组装 → 注入 → 消费`。
低层不 import 高层；strategy 只依赖第 1 层的 raw / base / board / team / tetris / torch / theme。

## 2. 文件地图（v6.2 实拍）

| 层 | 路径 | 关键符号 | 职责 |
| --- | --- | --- | --- |
| L1 | `lib/core/theme/tokens/colors.dart` | — | barrel：聚合各子目录 |
| L1 | `lib/core/theme/tokens/color/raw/` | `RawColors` | 跨主题中性骨架：pureWhite/nearBlack/9 档 neutral/shadow alpha |
| L1 | `lib/core/theme/tokens/color/base/` | `BaseColors` | 跨主题锁定的功能色 + 国际识别色（含 pieceI..L → avatar1..6 别名） |
| L1 | `lib/core/theme/tokens/color/board/` | 棋盘专属 token | — |
| L1 | `lib/core/theme/tokens/color/team/` | 团队卡头像色 | — |
| L1 | `lib/core/theme/tokens/color/tetris/tetris.dart` | `TetrisColors` | **v6.2 特例**：4 角色全 native const（棋盘环境 + 7 方块识别色 Map 1..7） |
| L1 | `lib/core/theme/tokens/color/torch/` | 灯具护眼色 | — |
| L1 | `lib/core/theme/tokens/color/theme/{zen,purple,ink,rose,lemon}.dart` | `ZenColors` / `PurpleColors` / ... | **5 套 ColorScheme + AppColorsExtension 调色板**（每主题一文件） |
| L1 | `lib/core/theme/tokens/color/app_colors_extension.dart` | `AppColorsExtension` | 抽象：13 状态色 + 8 分类色板 |
| L2 | `lib/core/theme/colors/strategy/color_strategy/` | `ColorStrategy` | 6 核心角色 + scheme 兜底；`@immutable` + `==`/`hashCode` |
| L2 | `lib/core/theme/colors/strategy/color_strategy/themes/default.dart` | `DefaultColorStrategy` | 完全从 scheme 派生 + 单例缓存（`DefaultColorStrategy(scheme: ...)`） |
| L2 | `lib/core/theme/colors/strategy/board_color_strategy/` | `BoardColorStrategy` | 11 棋盘角色 |
| L2 | `lib/core/theme/colors/strategy/board_color_strategy/themes/default.dart` | `DefaultBoardColorStrategy` | 棋盘角色从 scheme 派生 + 单例缓存（`.of(scheme)`） |
| L2 | `lib/core/theme/colors/strategy/tetris_colors_strategy/` | `TetrisColorsStrategy` | 4 角色抽象（棋盘环境 + 7 方块识别色） |
| L2 | `lib/core/theme/colors/strategy/tetris_colors_strategy/themes/default.dart` | `DefaultTetrisColorsStrategy` | **v6.2 修正**：4 角色全 native const（不跟主题），单例缓存（`.of(scheme)`） |
| L2 | `lib/core/theme/colors/strategy/team_avatar_strategy/` | `TeamAvatarStrategy` | 6 头像色（识别色锁定，不跟主题） |
| L2 | `lib/core/theme/colors/strategy/team_avatar_strategy/themes/default.dart` | `DefaultTeamAvatarStrategy` | const 构造，无 scheme 依赖 |
| L2 | `lib/core/theme/colors/strategy/torch_protect_strategy/` | `TorchProtectStrategy` | 10 护眼色预设 |
| L2 | `lib/core/theme/colors/strategy/torch_protect_strategy/themes/default.dart` | `DefaultTorchProtectStrategy` | 从 scheme 派生 + 单例缓存 |
| L2.5 | `lib/core/theme/colors/factory.dart` | `ThemeStrategyFactory` | 编译期安全工厂（switch 表达式），5 strategy 统一入口 |
| L2.5 | `lib/core/theme/extensions/*.dart` | `*StrategyExtension` | 5 个 ThemeExtension 注入器：只存 strategy 实例，lerp 用 50% 阈值离散切换 |
| L3 | `lib/core/theme/component/` | 复合组件样式 | — |
| 组装 | `lib/core/theme/app_theme.dart` | `AppTheme.getThemeData(mode)` | switch 映射 mode → scheme + ext + cardShadow，`_buildTheme` 组装 ThemeData + 5 个 strategy 注入 |
| 状态 | `lib/core/theme/state/theme_provider.dart` | `ThemeNotifier` / `themeNotifierProvider` / `themeDataProvider` / `materialThemeModeProvider` | Riverpod 状态单一源 |
| 消费 | `lib/widgets/context_colors.dart` | `ColorStrategyContext` | `context.colors` → 6 角色（三层兜底） |
| 消费 | `lib/widgets/context_board_colors.dart` | `BoardColorContext` | `context.boardColors` → 11 棋盘角色 |
| 消费 | `lib/widgets/context_tetris_colors.dart` | `TetrisColorsContext` | `context.tetrisColors` → 4 角色（双层兜底：extension → factory） |
| 消费 | `lib/widgets/context_team_avatar_colors.dart` | `TeamAvatarContext` | `context.teamAvatar` → 6 头像色 |
| 消费 | `lib/widgets/context_torch_protect_colors.dart` | `TorchProtectContext` | `context.torchProtect` → 10 护眼色 |

## 3. 数据流向（一次主题切换的完整链路）

```
① 定义层（编译期常量，无运行时）
   ZenColors.scheme · ZenColors.appColors            ← lib/core/theme/tokens/color/theme/zen.dart
            │ getThemeData(AppThemeMode.zen)
② 工厂组装 app_theme.dart
   _buildTheme(scheme, ext, cardShadow)
   → ThemeStrategyFactory.create 5 个 strategy（color/board/tetris/teamAvatar/torchProtect）
   → 5 个 StrategyExtension 挂到 ThemeData.extensions
            │ themeDataProvider ref.watch(themeNotifierProvider)
③ 状态 state/theme_provider.dart
   ThemeNotifier.state = AppThemeMode        ← main() 前 hydrate() 注入持久值
   setMode() → state 更新 → themeDataProvider 重建 → MaterialApp 换 ThemeData
            │ MaterialApp(theme: ref.watch(themeDataProvider))
④ 注入 ThemeData.extensions
   Theme.of(context).extension<ColorStrategyExtension>() 等读回 5 个 strategy
            │ 兜底：extension 为 null → factory 单例（绝不崩溃）
⑤ 消费 组件读颜色
   context.colors.accent / .textMuted …                    （6 角色）
   context.colors.scheme.primaryContainer …                 （scheme 兜底）
   context.boardColors.player1Stone / .winHighlight …       （棋盘）
   context.tetrisColors.pieceBackground / .pieceColors[7]  （俄罗斯方块，4 角色，跨主题锁定）
   context.teamAvatar.avatars[i]                            （团队卡 6 头像，跨主题锁定）
   context.torchProtect.presets[i]                          （护眼色，从 scheme 派生）
   Theme.of(context).colorScheme.error …                    （M3 标准）
   Theme.of(context).extension<AppColorsExtension>().category …（分类/状态）
```

**时序要点**：切主题 → Notifier state 变化 → 派生 Provider 重建 ThemeData → `MaterialApp` 换新 Theme → 全树 `Theme.of` 读新 scheme → 3 个 scheme-派生 strategy（color/board/torchProtect）返回新实例 → 依赖它的 widget rebuild。
**2 个 native-const strategy（tetris/teamAvatar）切主题不变**（玩家靠颜色识别，跨主题锁定）。

策略切换是**离散事件**：所有 `*StrategyExtension.lerp` 用 `t < 0.5 ? this : other`，**不做跨色插值**（注释明确说明避免渐变鬼影）。

## 4. 五条消费通道怎么选

| 通道 | 读取方式 | 数据源 | 角色数 | 典型使用者 |
| --- | --- | --- | --- | --- |
| `context.colors` | `ColorStrategyExtension` | scheme 派生 | 6 核心 + scheme 兜底 | 页面 / 卡片 / 对话框 / 列表 |
| `context.boardColors` | `BoardColorStrategyExtension` | scheme 派生 | 11 棋盘角色 | gomoku / reversi / jungle_chess 棋盘 |
| `context.tetrisColors` | `TetrisColorsStrategyExtension` | **native const** | 4 角色（棋盘 + 方块） | tetris 棋盘（见 [[special-cases]]） |
| `context.teamAvatar` | `TeamAvatarStrategyExtension` | **native const** | 6 头像色 | team_card 团队卡 |
| `context.torchProtect` | `TorchProtectStrategyExtension` | scheme 派生 | 10 护眼色预设 | torch 护眼灯 |
| `Theme.of(...).colorScheme.X` | M3 标准 | scheme | primary/secondary/tertiary/surface/error… | 跨主题一致性要求高的壳层 |
| `AppColorsExtension` | `Theme.of(...).extension<>()` | scheme | success/warning/info + category(8) | 图表 / 标签分类 |

> **决策速查**：能用 `Theme.of(context).colorScheme.X` 的优先用；需语义封装的用 `context.colors`；棋盘用 `context.boardColors`；特例（tetris/teamAvatar/torch）走各自通道；图表分类用 `AppColorsExtension.category`。
> 详细判定流：[[extension]] §4 表 + [[color-usage-audit]] §6。

## 5. 关键设计决策（改代码前必读）

1. **单例缓存**：`DefaultColorStrategy(scheme: ...)` / `DefaultBoardColorStrategy.of(scheme)` 等只在 scheme 不同时重建实例——避免作为 ThemeExtension 被反复 new 导致 GC 抖动。**所有策略类唯一入口是各自的 `factory` / `.of()` 工厂**。
2. **`==` / `hashCode` 已按角色重写**：相同方案复用实例 → Flutter 识别相同策略 → 避免不必要 rebuild。`TetrisColorsStrategy` 因为 4 角色全 const，`==` 永远成立 → 跨主题共用同一实例。
3. **ThemeExtension 只存实例不存 BuildContext**（防止内存泄漏）；`lerp` 强制返回 `this` 或 `other` 而非 `Color.lerp` 插值。
4. **多层兜底**：每个 `context.X` = extension 命中 → 否则 factory 单例，**绝不返回 null / 绝不崩溃**。
5. **compile-time factory**：`ThemeStrategyFactory.create*` 用 switch 表达式杜绝运行时 KeyError。
6. **`SURFACE` 与 `TEAM` 角色重叠靠独立通道解决**：`scheme.surface` 同时是页面卡片底又是棋盘底 → 棋盘单独走 `boardColors`；胜方高亮需要跳出主题 → `winHighlight = scheme.tertiary`（互补色）。
7. **特例 strategy 走 native const**：玩家靠颜色识别方块（tetris）/ 头像（team card）→ 跨主题锁定。强行挂到 scheme 上 = L 块越界 + 颜色错乱（v6.2 真实踩坑）。详见 [[special-cases]]。
8. **保留的硬编码豁免**（属设计决策）：`lib/core/surround_game` 与 `lib/core/reversi` 用各自 `BoardThemeData` 令牌（86 处 hex，warm/cool 两套预设，30+ 角色），与 `context.boardColors` 平级。

## 6. v6.2 架构陷阱

### 6.1 不要给"识别色"业务接 scheme 派生

**症状**：tetris 棋盘 / 团队卡头像在切主题时颜色漂移，I 块显示琥珀色（L 块直接消失）。

**根因**：`pieceColors` 改 `List<Color>` 索引 0..6，强行从 scheme 派生，但 engine / Lua 协议始终用 1..7 → off-by-one + 越界。

**修法**：见 [[special-cases]] —— 用 `Map<int, Color>` 1..7 + native const 锁定。

**踩坑案例**：`fix(tetris): revert palette to native + fix pieceColors off-by-one`（commit 24d91ea1，2026-08-29）。

### 6.2 嵌套 MaterialApp 不继承 colorScheme（症状：主题色不生效）

**症状**：demo 页里有局部 `MaterialApp` 包裹。切主题后，整个 app 主题变了，但这个 demo 里所有读 `Theme.of(context).colorScheme.X` 的组件仍是 Flutter 默认配色。

**根因**：内层 `MaterialApp.theme` 只复制 4 个字段（`scaffoldBackgroundColor` / `canvasColor` / `primaryColor` / `splashColor` 等），**没复制 `colorScheme` 也没复制 5 个 extensions**。内层子树 `Theme.of()` 返回的就是 Flutter 默认 ThemeData，不是父级。

**修法**：
```dart
final base = Theme.of(context); // 拿当前主题
return MaterialApp(
  theme: base.copyWith(
    scaffoldBackgroundColor: context.colors.surface,
    canvasColor: context.colors.surface,
    primaryColor: context.colors.accent,
    splashColor: context.colors.accent.withValues(alpha: 0.1),
    highlightColor: context.colors.accent.withValues(alpha: 0.05),
    // 不要重置 colorScheme/extensions —— base.copyWith 会自动继承
  ),
  home: ...,
);
```
**教训**：能用 `Theme` 注入解决就别套 `MaterialApp`。实在要套，必须 `base.copyWith()` 继承完整 ThemeData。

**踩坑案例**：`lib/lab/demos/clock_demo.dart`。

### 6.3 Navigator.push 后 Provider 树被隔断

**症状**：某个 `ConsumerStatefulWidget` / 用 `Provider.of<>(context)` 取 provider 的页面，被 `Navigator.push` 推到新 route 后，打开立即红屏 `ProviderNotFoundException` 或白屏。

**根因**：新 route 的 `BuildContext` 祖先链 ≠ 原 MultiProvider 子树。`Navigator.push(MaterialPageRoute(builder: (_) => XxxPage()))` 里 `builder` 的 context 不会继承原页面所在的 Provider 子树。

**修法**（`provider` 包）：
```dart
final p = context.read<XxxProvider>();
Navigator.of(context).push(MaterialPageRoute(
  builder: (_) => ChangeNotifierProvider<XxxProvider>.value(
    value: p,
    child: const XxxPage(),
  ),
));
```
多个 provider 同理用 `MultiProvider`。

**踩坑案例**：`lib/lab/demos/calendar_demo.dart` → `CalendarSettingsPage`。

### 6.4 调试步骤（不能只改颜色——先排除树问题）

碰到"主题色不对"的页面，按下面顺序排查：

1. **是不是树问题？** 当前页面或父页面有没有嵌套 `MaterialApp` / `Navigator.push` 出去的 route？是 → 套用 §6.2 / §6.3 修法，不是颜色层问题。
2. **是不是该走 native-const 通道的走成 scheme 派生？** 切主题后该不动的角色跟着变了（如 tetris 棋盘）→ 走 [[special-cases]] 修正。
3. **是不是 token/strategy 没拿到？** 看 `Theme.of(context).colorScheme.X` 是否为 Flutter 默认值（蓝紫 primary）；看 `context.colors` 是否为 null。是 → strategy 注入问题。
4. **是不是组件自己写了裸 hex？** `grep -rn "Color(0xFF" <file>` + 检查 `Colors.X`。是 → 走迁移 SOP（[[extension]] §4）。
5. **是不是该用 channel 但没用？** 列表/卡片缺 `context.colors.surface` 时检查是不是手动传了颜色。是 → 改读 scheme。
