# 子 ref D：特例策略（识别色锁定，不跟 5 主题）

> 从 [SKILL.md](../SKILL.md) 导航进入。本文讲 **为什么 tetris / teamAvatar 走 native const、不接 scheme 派生，以及怎么写下一个类似的"识别色锁定"业务**。
> 系统分层/文件地图先看 [[architecture]]；迁移 SOP 见 [[extension]]。

## 0. 什么业务该走"识别色锁定"通道

判定 3 问（满足任一即适用）：

1. **玩家靠颜色识别对象吗？** 方块（I=青 / O=黄 / T=紫 / ...）、棋子（黑/白）、头像（6 色识别）—— 切主题变了，玩家会"找不到 I 块"。
2. **数据有"国际标准色"吗？** 2048 原版数字色、Othello 绿盘、莫兰迪色卡——切主题违反标准 = 误认。
3. **业务要求"色 = 身份"吗？** 团队卡头像（每人一个色）—— 切主题换色 = 团队身份错乱。

满足任一 → **走 native const，不接 scheme 派生**。

> 反例：护眼灯（torch）**应该跟主题**——暗色主题下希望护眼色也偏暖柔，亮色主题下希望更鲜活。所以 `TorchProtectStrategy` 走 scheme 派生。

## 1. tetris 棋盘配色（v6.2 真实踩坑的范例）

### 1.1 业务背景

俄罗斯方块 7 方块是**国际通用识别色**：
- I = cyan（青色长条）
- O = yellow（黄色方块）
- T = purple（紫色 T 形）
- S = green（绿色 S 形）
- Z = red（红色 Z 形）
- J = blue（蓝色 J 形）
- L = orange（橙色 L 形）

历史 commit `6e681248` 时期用 `Map<int, Color>` 1..7 索引（与 engine / Lua 协议一致），跨主题锁定（深色 slate-900 棋盘 + 7 个国际识别色）。

v6.2 重构成 `List<Color>` 0..6 + 从 scheme 派生，**直接踩坑**：
- L 块 `pieceColors[7]` 越界 RangeError → **L 块消失**
- 1..6 块索引错位 → **棋盘颜色全乱**（I 变琥珀、O 变紫色、...）
- 棋盘环境跟主题漂移 → **切 zen 主题棋盘变白底、切 purple 变深底**

### 1.2 修复（commit 24d91ea1）

**4 角色全走 native const**（`lib/core/theme/tokens/color/tetris/tetris.dart`）：

```dart
class TetrisColors {
  /// 方块顶部 3D 亮面（深色棋盘上用白 @ 28%，跨主题锁定）
  static const Color cellHighlight = Color(0xB3FFFFFF);

  /// 棋盘底色（slate-900 深色，跨主题锁定）
  static const Color pieceBackground = Color(0xFF0F172A);

  /// 网格线（白色 5% 透明，跨主题锁定）
  static const Color pieceGridLine = Color(0x0DFFFFFF);

  /// 7 方块识别色（按 kPieceI..kPieceL 索引 1..7，跨主题锁定）
  /// Map 强制要求显式索引，结构上避免 0..6 列表的 off-by-one。
  static const Map<int, Color> pieceColors = {
    /*kPieceI*/1: Color(0xFF22D3EE), // cyan-400
    /*kPieceO*/2: Color(0xFFFACC15), // yellow-400
    /*kPieceT*/3: Color(0xFFA855F7), // purple-500
    /*kPieceS*/4: Color(0xFF22C55E), // green-500
    /*kPieceZ*/5: Color(0xFFEF4444), // red-500
    /*kPieceJ*/6: Color(0xFF3B82F6), // blue-500
    /*kPieceL*/7: Color(0xFFF97316), // orange-500
  };
}
```

**`Map<int, Color>` 索引 1..7 是结构上防 off-by-one 的关键**——`pieceColors[0]` 返回 `null`（不是 RangeError），强制 `!` 编译期 fail；`pieceColors[7]` 命中 L 块正常返回橙色。

**Default 实现不参与派生**（`lib/core/theme/colors/strategy/tetris_colors_strategy/themes/default.dart`）：

```dart
class DefaultTetrisColorsStrategy extends TetrisColorsStrategy {
  @override
  final ColorScheme scheme; // 仍保留作接口契约，但不再用于派生

  static DefaultTetrisColorsStrategy? _cached;

  factory DefaultTetrisColorsStrategy.of(ColorScheme scheme) { ... }

  @override
  Color get cellHighlight => TetrisColors.cellHighlight;     // native const
  @override
  Color get pieceBackground => TetrisColors.pieceBackground; // native const
  @override
  Color get pieceGridLine => TetrisColors.pieceGridLine;     // native const
  @override
  Map<int, Color> get pieceColors => TetrisColors.pieceColors; // native Map
}
```

**`context.tetrisColors` 仍走 ThemeExtension 双层兜底**（保留架构对称）：

```dart
extension TetrisColorsContext on BuildContext {
  TetrisColorsStrategy get tetrisColors {
    final ext = Theme.of(this).extension<TetrisColorsStrategyExtension>();
    if (ext != null) return ext.strategy;
    return DefaultTetrisColorsStrategy.of(Theme.of(this).colorScheme);
  }
}
```

切任意主题 `context.tetrisColors` 4 角色完全不变（已用 `tetris_strategy_native_test.dart` 锁定）。

### 1.3 渲染端修法（4 处 `pieceColors[t]!`）

`board.dart` 把 `pieceColors[t]` 改成 `pieceColors[t]!`——`Map.get` 返回 `Color?`，`!` 强制非空（编译期 fail on future off-by-one 复发）：

```dart
// 堆积格 / ghost / 下落块 / preview 共 4 处
_paintCell(canvas, cellW * x, cellH * y, cellW, cellH, pieceColors[t]!);
```

`_BoardPainter.shouldRepaint` 还原历史 `=> true`（`grid` 是 engine 内部 mutate 的同一引用，引用比较不可靠，恒重绘零漏帧）——这是 v6.2 引入的另一个隐性 bug，导致"棋盘漂移后不重绘"。

## 2. 怎么写下一个"识别色锁定"特例 strategy

以「2048 数字色板」为例（假设要加）：

### 2.1 新增 token 数据源

`lib/core/theme/tokens/color/<new>/<new>.dart`：
- 静态 const 角色定义（裸 hex 直接放 token 文件，**不豁免注释**——这是架构决策保留的"特例"）
- 文件顶部注释说明"为什么是特例"（业务理由 + 跨主题锁定）

### 2.2 抽象 strategy

`lib/core/theme/colors/strategy/<new>_strategy/<new>_strategy.dart`：
- `@immutable abstract class <New>Strategy`
- 角色 getter + `==`/`hashCode` 按角色重写
- 接口契约保留 `ColorScheme get scheme`（即使不参与派生，与其他 strategy 对称）

### 2.3 默认实现

`lib/core/theme/colors/strategy/<new>_strategy/themes/default.dart`：
- `class Default<New>Strategy extends <New>Strategy`
- 4 角色 getter 全 `=> <New>Colors.<role>`（native const）
- 工厂 `Default<New>Strategy.of(scheme)` 返回 const 实例（可选单例缓存）

### 2.4 ThemeExtension 注入器

`lib/core/theme/extensions/<new>_strategy_extension.dart`：
- 仿 `TetrisColorsStrategyExtension` 写
- `lerp` 用 50% 阈值离散切换（不要插值）

### 2.5 factory + app_theme 注册

`lib/core/theme/colors/factory.dart`：
- 加 `static <New>Strategy create<New>Strategy(ColorScheme scheme) => Default<New>Strategy.of(scheme);`
- 顶部注释"5 个 strategy 角色分工"块补一行

`lib/core/theme/app_theme.dart`：
- `_buildTheme` 里加 `final <new>Strategy = ThemeStrategyFactory.create<New>Strategy(scheme);`
- `extensions: [...]` 列表加 `<New>StrategyExtension(<new>Strategy)`

### 2.6 消费入口

`lib/widgets/context_<new>_colors.dart`：
- `extension <New>Context on BuildContext { <New>Strategy get <new>Colors => ... }`
- 双层兜底：extension → factory 单例

### 2.7 测试

`test/lab/<your_module>/<new>_palette_test.dart`（本地 .gitignore）：
- 颜色 hex 与原始来源逐项断言
- 索引范围 / 越界 / null 行为
- 跨主题锁定：`schemeA.<new>Colors == schemeB.<new>Colors`（同一 const 实例）

### 2.8 检查清单

- [ ] token 文件含"为什么是特例"业务注释
- [ ] 抽象 strategy 接口完整、`==`/`hashCode` 一致
- [ ] 默认实现不参与 scheme 派生
- [ ] ThemeExtension / factory / app_theme / context_*.dart 全链路注册
- [ ] 渲染端用 `Map[key]!` / `List[idx]` 等结构化索引，**避免可变长度列表 + scheme 派生**
- [ ] 至少 1 个跨主题锁定测试 + 1 个 off-by-one 保护测试
- [ ] audit 表（[[color-usage-audit]] §1）补一行：`<your_module>` 用色通道

## 3. 已有特例 strategy 索引

| strategy | 业务 | 数据源 | 文件 |
| --- | --- | --- | --- |
| `TetrisColorsStrategy` | 俄罗斯方块 4 角色（棋盘 + 7 方块） | native const | `tokens/color/tetris/tetris.dart` |
| `TeamAvatarStrategy` | 团队卡 6 头像色 | native const | `tokens/color/team/` |
| `TorchProtectStrategy` | 灯具护眼 10 色预设 | **scheme 派生** | `tokens/color/torch/` |

注意：torch 虽然有"护眼"标签但**不锁主题**——切主题会变（暗主题下护眼色更柔、亮主题下更鲜）。如果未来要锁，参考本 ref §2 改造。
