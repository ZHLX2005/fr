# A08 · 胶囊与方圆角 CTA

> 何时读：纠结按钮要不要 `StadiumBorder` / `borderRadius: 999`；远程输入 brief 写「12–14 圆角，不用全胶囊」时；大厅主按钮又要全胶囊时。
>
> 原型对照：`remotetype-input.html`（方圆角）vs `feature-list-and-lobby.html` / `game-surfaces-palettes.html`（仪式胶囊）。

## 一、实现思路

### 判决表（先场景后形状）

| 场景 | 几何 | 半径 / shape | 色 |
| --- | --- | --- | --- |
| 主壳 dock 容器、搜索 pill、筛选 chip.on | **全胶囊** | `StadiumBorder` / 999 | glass / surface |
| 大厅「开始匹配」等**仪式主 CTA** | **全胶囊** | 999，高度 ~48–52 | `tertiary`（clay）或 `primary`（看页面） |
| 远程输入 chrome、房间就绪/发牌次级钮、工具页操作 | **方圆角** | **10–14**（mic **20** @ 64×64） | primary / tonal |
| 图标按钮、ghost 小 pill | **方圆角** | **10–12** | primaryContainer |

**一句话**：工具密集区忌全胶囊；仪式入口 / 壳层导航可以用。

### Flutter 片段

```dart
// 仪式胶囊
FilledButton(
  style: FilledButton.styleFrom(
    minimumSize: const Size.fromHeight(50),
    shape: const StadiumBorder(),
    backgroundColor: cs.tertiary,
    foregroundColor: cs.onTertiary,
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

- 仪式胶囊 = **该填充就填充**（内容/仪式页），不走 A01 描边减负。
- 密集工具钮若已是方圆角仍显「左重右轻」→ 再考虑 [[Ea03-边框强调式减负]]。

## 二、踩坑总结

| 坑 | 后果 | 正确做法 |
| --- | --- | --- |
| 远程输入所有按钮改 stadium | 原型明确讨厌「全胶囊 chrome」 | chrome 12–14；仅 mic 略大方圆角 20 |
| 大厅主 CTA 做成方圆角小按钮 | 丢失仪式重心 | 大厅主按钮用胶囊 + clay/tertiary |
| Mic 用 FAB 默认圆形 | 与原型 squircle 不一致 | 显式 `BorderRadius.circular(20)` |
| CTA 字色写死 `Colors.white` | lemon/purple 主题 `onPrimary` 非白 | 始终 `onPrimary` / `onTertiary`（见 [[Ea14-游戏表面ColorScheme契约]]） |

## 关联

- Zen 浮卡 → [[Ea08-Zen浮卡少描边]]
- 大厅就绪页 → [[Ea11-大厅与房间就绪]]
