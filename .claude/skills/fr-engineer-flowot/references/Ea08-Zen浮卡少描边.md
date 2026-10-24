---
name: zen-float-card
description: 什么时候做「白卡浮在浅底、靠阴影分层、少描边」的浮卡时读——Zen 浮卡配方、token 对照、组内分隔与图标瓦规则。
---

# Zen 浮卡少描边

> 何时读：做设置列表、设备/电脑 peer 列表、大厅表单卡、茶禅暖底工具页；原型 brief 写「白卡浮在浅底、靠阴影分层、少描边」时。
>
> 原型：`docs/prototypes/feature-list-and-lobby.html`、`remotetype-input.html`。

## 一、实现思路

### 原则（来自原型 header）

1. 大留白 2. 强调色稀用（clay/tertiary 只点睛） 3. 白卡浮在略深暖底 4. 统一大圆角 5. 每屏一个视觉重心 6. 字重层级清晰

### Token 对照（Zen 默认 → Flutter）

| 原型 CSS | 约值（仅文档） | Flutter |
| --- | --- | --- |
| `--bg` | `#F2EFE7` / `#F4F1EA` | `scheme.surface` / scaffold |
| `--surface` / `--card` | `#FFFCF6` | `context.colors.surface` 或 `scheme.surfaceContainerLowest` |
| `--tray` | `#EFEBE2` | `scheme.surfaceContainerHighest` |
| `--sage` / primary | `#7A9A7E` | `scheme.primary` |
| `--clay` | `#A0594A` | `scheme.tertiary`（稀用） |
| `--muted` | `#8A8475` | `context.colors.textMuted` / `onSurfaceVariant` |
| 卡片半径 | **16–24** | `BorderRadius.circular(16\|18\|24)` |
| 阴影 | 暖棕低 alpha 双层 | `BoxShadow` + `scheme.shadow.withValues(alpha: 0.04~0.12)` |

> 实现时**禁止**把上表 hex 写进 `lib/`；只消费 scheme。hex 仅对照原型。

### 浮卡配方

```dart
final c = context.colors;
final cs = c.scheme;
Material(
  color: c.surface, // 浮卡；页底用 surfaceContainerHighest（原型 --bg / --card）
  elevation: 1,
  shadowColor: cs.shadow.withValues(alpha: 0.06),
  surfaceTintColor: Colors.transparent, // 禁 M3 elevation 染 primary 色
  borderRadius: BorderRadius.circular(18),
  child: InkWell(
    borderRadius: BorderRadius.circular(18),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: row, // 左 tint 图标瓦 + 文案 + 右侧弱 hint
    ),
  ),
);
```

- **组内分隔**：用 hairline（`outline` @ 0.06）或竖向间距，**不要**给每行再描一圈边。
- **`surfaceTintColor: Colors.transparent` 已被手抄多处**：全仓 12 处（`grep -rn "surfaceTintColor: Colors.transparent" lib/`），其中 10 处在 `lib/core/remotetype/`（`rt_page.dart`、`ui/rt_shortcut_bar.dart`、`ui/rt_input_view.dart`、`ui/rt_pairing_view.dart`、`ui/rt_connecting_overlay.dart`），另 2 处在 `lib/lab/demos/session_host_demo.dart` 与 `lib/screens/profile/lab/demo_detail_page.dart`。同一段浮卡配方重复这么多遍 → **建议抽一个 `ZenFloatCard` widget**（内含 `surface` 底 + `surfaceTintColor: transparent` + 圆角 18 + 阴影），新卡直接复用，别再复制粘贴。
- **图标瓦**：`primaryContainer` 底 + `onPrimaryContainer` icon，圆角 ~14；在线态可叠 8–10px primary 圆点。
- **整行可点**：功能列表/电脑列表不要再塞显式「连接」主按钮（见 RemoteType 统一登录路径）。

### 刷新等次级操作

小 pill：`primaryContainer` 底 + `onPrimaryContainer` 字，圆角 **12**，字重 700，字号 12——不是 FilledButton。

## 二、踩坑总结

| 坑 | 后果 | 正确做法 |
| --- | --- | --- |
| 卡片再用 `Border.all(outline)` 加厚 | 茶禅「少描边」失效，变 demo 网格 | 阴影分层；边框只留给选中态或就绪态 |
| Scaffold / 浮卡都用 `surface`，且 Material 带 elevation tint | 卡与页同色或发绿/发紫，不像奶油浮卡 | 页底 `surfaceContainerHighest`；浮卡 `surface` + `surfaceTintColor: transparent` |
| Composer `TextField` 只设 `border: none` | 焦点仍可能出 outline | `enabled/focused/errorBorder` 全 `InputBorder.none`，`filled: false` |
| 每屏多个 clay CTA | 无重心 | clay/tertiary 每屏最多一个仪式主按钮（见 [[Ea10-胶囊与方圆角CTA]]） |
| 导航 icon 彩虹色 | 与主文档「导航统一主题色」冲突 | 统一 `primary` / `primaryContainer` |
| 把 [[Ea03-边框强调式减负]] 套到浮卡外框 | 双边框打架 | 描边减负管**按钮/icon 容器**；浮卡外框走本方案 |

## 关联

- 功能型减负按钮 → [[Ea03-边框强调式减负]]
- 内容封面 → [[Ea06-商店式内容页]]
- 全主题契约 → [[Ea14-游戏表面ColorScheme契约]]
