---
name: Ea10-胶囊与方圆角CTA
description: FR 主 CTA 的胶囊 / 方圆角形状决策与当前实现真值。当纠结按钮要不要 StadiumBorder、远程输入 brief 写「12–14 圆角」时、或要改房内就绪 CTA 时读取。
---

# Ea10 — 胶囊与方圆角 CTA

> 何时读：纠结按钮要不要 `StadiumBorder` / `borderRadius: 999`；远程输入 brief 写「12–14 圆角，不用全胶囊」时；大厅主按钮又要全胶囊时。
>
> 原型对照：`remotetype-input.html`（方圆角）vs `feature-list-and-lobby.html` / `game-surfaces-palettes.html`（仪式胶囊）。

## 一、实现思路

### 判决表（先场景后形状）

| 场景 | 几何 | 半径 / shape | 色 | 当前实现 |
| --- | --- | --- | --- | --- |
| 主壳 dock 容器、搜索 pill、筛选 chip | **全胶囊** | `StadiumBorder` / 999 | glass / surface | `lib/core/ui/shell/quick_nav_bottom_bar.dart` |
| 大厅「开始匹配」等**仪式主 CTA** | **全胶囊** | 999，高度 56 | **`primary`** | `lib/core/game_kit/lobby/_lobby_form.dart:251` |
| **房间就绪 / 发牌 CTA** | **全胶囊** | `StadiumBorder`，高度 50 | `primary` / `primary` 描边 | `lib/core/ui/game/game_ready_style.dart:190,200`（`GameReadyCtaStyle.filled/outlined`） |
| 远程输入 chrome、工具页操作 | **方圆角** | **10–14**（mic **20** @ 64×64） | primary / tonal | 远程输入域 |
| 图标按钮、ghost 小 pill | **方圆角** | **10–12** | primaryContainer | 散落各模块 |

**一句话**：工具密集区忌全胶囊；仪式入口 / 壳层导航 / 房内就绪 CTA 可以用。

> ⚠️ **历史文档更正**：本文件此前写「房间就绪/发牌次级钮 → 方圆角 10–14」「房内不用全胶囊以免抢大厅仪式」。**与代码不符**——房内就绪 CTA 现为 `StadiumBorder` 全胶囊（`GameReadyCtaStyle`），大厅主 CTA 同为 `StadiumBorder`。以代码为真值；「房内应改回方圆角」是**未落地的设计建议**，不是现状。

### 颜色注意

- 大厅主 CTA 用 **`primary`**；`lib/core/game_kit/lobby/_lobby_form.dart:245-246` 的注释明确「色走 theme primary（禁止 tertiary 反色抢戏）」。写 `tertiary`（clay）会让主 CTA 与主题主色脱节。
- CTA 字色用 `onPrimary` / `onTertiary`，不写死 `Colors.white`（lemon/purple 主题的 `onPrimary` 非白）。

### Flutter 片段

```dart
// 仪式胶囊（大厅主 CTA）
FilledButton(
  style: FilledButton.styleFrom(
    minimumSize: const Size.fromHeight(56),
    elevation: 0,
    shape: const StadiumBorder(),
  ),
  onPressed: onStart,
  child: const Text('开始匹配'),
);

// 工具方圆角（mic）
Material(
  color: listening ? cs.tertiary : cs.primary,
  borderRadius: BorderRadius.circular(20), // 不是 Stadium
  child: InkWell(
    borderRadius: BorderRadius.circular(20),
    onTap: onMic,
    child: const SizedBox(
      width: 64,
      height: 64,
      child: Icon(Icons.mic, size: 26),
    ),
  ),
);
```

### 与填充策略的关系

- 仪式胶囊 = **该填充就填充**（内容/仪式页），不走 [[Ea03-边框强调式减负]] 的描边减负。
- 密集工具钮若已是方圆角仍显「左重右轻」→ 再考虑 [[Ea03-边框强调式减负]]。

### 圆角档位与 token 的错位（待治理）

`lib/design_tokens/radius.dart` 的 `AppRadius` 档位是 **4 / 6 / 8 / 12 / 16 / 24**。
本文件与 Ea08/Ea09/Ea11 里出现的 **10 / 11 / 14 / 18 / 20 / 22 / 28** **全部不在 token 档位内**，且无归一规则。
→ 抽 `AppShapeExtension`（ctaRadius / ctaHeight / pillRadius 等）之前必须先裁决：是归一到 token 档位，还是把这些值登记为「形状特例」。**否则会把不一致的数值固化进扩展。**

## 二、踩坑总结

| 坑 | 后果 | 正确做法 |
| --- | --- | --- |
| 远程输入所有按钮改 stadium | 原型明确讨厌「全胶囊 chrome」 | chrome 12–14；仅 mic 略大方圆角 20 |
| 大厅主 CTA 做成方圆角小按钮 | 丢失仪式重心 | 大厅主按钮用胶囊 + `primary` |
| Mic 用 FAB 默认圆形 | 与原型 squircle 不一致 | 显式 `BorderRadius.circular(20)` |
| CTA 字色写死 `Colors.white` | lemon/purple 主题 `onPrimary` 非白 | 始终 `onPrimary` / `onTertiary`（见 [[Ea14-游戏表面ColorScheme契约]]） |
| 按文档给房内 CTA 改方圆角 | 与 `GameReadyCtaStyle` 的既有实现冲突 | 先改 `game_ready_style.dart` 真值，再改文档；两者不能各改一半 |

## 关联

- Zen 浮卡 → [[Ea08-Zen浮卡少描边]]
- 大厅就绪页 → [[Ea11-大厅与房间就绪]]
- 房内就绪 CTA 的共享实现 → `lib/core/ui/game/game_ready_style.dart`
