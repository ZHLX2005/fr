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
| 判断某处能不能写裸 hex | 豁免规则 | §5 |

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