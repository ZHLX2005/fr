---
name: ui-theme-architecture
description: 本项目 zen / purple / ink / rose / lemon 五主题色彩与 UI 主题架构的总入口。当需要理解主题系统怎么运作、改主题配色、扩展语义角色、迁移组件到主题通道、新增组件样式、或评审目录用色是否合规时触发。首页只做 ref 导航，架构细节按需读对应子 ref。
---

# UI 主题架构（ref 导航页）

本项目主题系统是一个 **4 分层 + 5 Strategy + 5 消费通道** 的色彩架构：

```
tokens(原料) → theme(色板) → strategy(策略) → component(组件)
     → app_theme 组装 → ThemeExtension 注入 → 5 个 context.* 消费
```

> **本页只做导航。** 要理解/改动主题，先按下面表格选对子 ref 再动手，不要靠本页推断细节。

## 何时读哪个 ref

| 场景 | 读哪份 | 路径 |
| --- | --- | --- |
| 刚接触主题系统，想知道它怎么分层、哪些文件、一次主题切换的数据如何流动 | [[architecture]] | `references/architecture.md` |
| 新增一套主题配色 / 新增强调色语义角色 / 新增组件样式 / 把既有硬编码迁移到主题通道 / 判断哪些 hex 要豁免 | [[extension]] | `references/extension.md` |
| 评审或改动某目录前，查该目录用色规模、迁移完整度、残留 hex 归属、Top 热点文件 | [[color-usage-audit]] | `references/color-usage-audit.md` |
| 想知道 tetris 棋盘配色为何"不跟 5 主题"、识别色策略怎么写 | [[special-cases]] | `references/special-cases.md` |

## 五策略速览（v6.2 架构，5 通道）

| strategy | 入口 | 角色数 | 数据源 | 适用于 |
| --- | --- | --- | --- | --- |
| `ColorStrategy` | `context.colors` | 6 核心 + scheme 兜底 | **从 scheme 派生** | 普通组件、页面、卡片 |
| `BoardColorStrategy` | `context.boardColors` | 11 棋盘专属 | **从 scheme 派生** | 棋牌棋盘 UI（gomoku/reversi/jungle） |
| `TetrisColorsStrategy` | `context.tetrisColors` | 4 角色（棋盘环境 + 方块色） | **native const（特例）** | 俄罗斯方块 |
| `TeamAvatarStrategy` | `context.teamAvatar` | 6 头像色 | **native const（识别色锁定）** | 团队卡 |
| `TorchProtectStrategy` | `context.torchProtect` | 10 护眼色预设 | **从 scheme 派生** | 灯具护眼 |

> **核心约定**：3 个 strategy 走"scheme 派生"（切主题 = 换 scheme = 自动重新派生）；2 个 strategy（tetris / teamAvatar）走"native const"（玩家靠颜色识别，跨主题锁定）。特例细节见 [[special-cases]]。

另有 `Theme.of(context).colorScheme.X`（M3 标准角色）与 `Theme.of(context).extension<AppColorsExtension>()`（状态色 + 分类色板）两条直连通道。

## 红线（不读 ref 也记住）

- **`lib/` 新增代码禁止裸 hex**（`Color(0xFF...)`）——走 scheme / 5 通道；确需硬编码必须带 `主题豁免` 注释说明业务理由。
- 单例缓存策略类**不要绕开**：`DefaultColorStrategy(scheme: ...)` / `DefaultBoardColorStrategy.of(scheme)` 等是唯一构造入口（已做 scheme 相等去重，避免 GC 抖动）。
- **特例策略不要走 scheme 派生**：tetris / teamAvatar 等"识别色锁定"业务，必须 native const；强行挂到 scheme 上 = L 块越界 + 颜色错乱（v6.2 真实踩坑，见 [[special-cases]]）。

## 引用索引

| ref | 何时读取 | 路径 |
| --- | --- | --- |
| [[architecture]] | 理解系统/查文件地图/看数据流时 | `references/architecture.md` |
| [[extension]] | 扩展主题/迁移代码/判定豁免时 | `references/extension.md` |
| [[color-usage-audit]] | 评审目录/查残留 hex/看迁移历史时 | `references/color-usage-audit.md` |
| [[special-cases]] | 理解 tetris / teamAvatar 为何不跟主题、怎么写"识别色锁定"业务时 | `references/special-cases.md` |
