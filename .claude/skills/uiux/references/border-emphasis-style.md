# Border-Emphasis 边框强调式（归档自 border-emphasis skill）

> 本文档原为 `.claude/skills/border-emphasis/SKILL.md` 的内容。合并入 uiux skill 后归档在此供历史参考。
>
> 何时读：改造纯色填充按钮/icon 容器 / 减负密集按钮区 / "左重右轻"时。

---

# 边框强调 (Border-Emphasis)

把"纯色填充"的 icon 容器 / 按钮改造为"浅 tint 底 + 同色描边 + 同色前景"，
降低视觉重量、平衡构图（典型痛点：左重右轻）。

## 何时触发

- 用户说"左重右轻""纯色太重""icon 纯色""避免纯色按钮""边框强调""描边式"
- 代码里出现下列"纯色"信号：
  - icon 容器用 `LinearGradient` / 饱和 `color` 填充 + 白色 `Icon`
  - `ElevatedButton(styleFrom(backgroundColor: Colors.X, foregroundColor: Colors.white))`
  - `FilledButton(styleFrom(backgroundColor: Colors.X, ...))`
  - 默认 `ElevatedButton`（主题色实心）出现在需要减负的密集按钮区

## 核心配方（三件套）

浅色 tint 背景 + 同色描边 + 同色前景。经验 alpha：

| 部位              | alpha                    | 说明                         |
| ----------------- | ------------------------ | ---------------------------- |
| tint 背景         | 0.08 ~ 0.12              | 给轮廓一点"存在感"，又不抢眼 |
| 描边              | 0.30 ~ 0.50（width 1.5） | 主视觉信号                   |
| 前景（icon/text） | color 本色               | 与描边同色，整体协调         |

### Icon 容器模板

```dart
final accent = Theme.of(context).colorScheme.primary; // 或功能色

Container(
  width: 52,
  height: 52,
  decoration: BoxDecoration(
    color: accent.withValues(alpha: 0.10),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.5),
  ),
  child: Icon(icon, color: accent, size: 24),
)
```

### Button 模板（OutlinedButton + helper）

```dart
/// color = 该操作的功能色
ButtonStyle _outlinedBtnStyle(Color color) =>
    OutlinedButton.styleFrom(
      foregroundColor: color,
      side: BorderSide(color: color.withValues(alpha: 0.5)),
    );

OutlinedButton.icon(
  onPressed: _download,
  icon: const Icon(Icons.download),
  label: const Text('下载'),
  style: _outlinedBtnStyle(Colors.blue),
)
```

## 颜色决策：装饰性 vs 功能性（最易错，必读）

**规则相反，不能一刀切。** 这是本 skill 最核心、最易翻车的判断：

| 元素类型                                  | 配色策略                                                       | 例子                     |
| ----------------------------------------- | -------------------------------------------------------------- | ------------------------ |
| **装饰性**（导航卡片 icon、纯展示） | **统一主题色** `Theme.of(context).colorScheme.primary` | profile 菜单卡片         |
| **功能性**（操作按钮）              | **撞色编码语义**                                         | APK / KV / 文件 tab 按钮 |

功能性语义色对照表（跨页面保持一致）：

| 色                         | 语义                  | 典型按钮                           |
| -------------------------- | --------------------- | ---------------------------------- |
| green                      | 主操作 / 成功 / 写入  | 安装、上传、设置                   |
| blue                       | 查询 / 接收 / 读取    | 检查更新、下载、获取               |
| orange                     | 暂停 / 警示           | 暂停、停止                         |
| **red**              | **危险 / 删除** | 取消、删除（**永远保留红**） |
| indigo / teal / deepPurple | 差异化 / 备用操作     | 浏览器下载、继续下载、媒体播放     |

## 错误案例（高频坑点）

| 错误操作                                                | 实际后果                            | 正确做法                                                   |
| ------------------------------------------------------- | ----------------------------------- | ---------------------------------------------------------- |
| 给**导航卡片**配彩虹独立色                        | 显幼稚、违和、不统一                | 导航 icon 用统一主题色                                     |
| 给**操作按钮**统一主题色                          | 功能无区分、层级丢失                | 按钮用撞色编码语义                                         |
| 用`.withOpacity(x)`                                   | analyze 报`deprecated_member_use` | 用`.withValues(alpha: x)`                                |
| 删除/取消按钮也去掉红色                                 | 危险操作失去警示语义                | 破坏性操作**永远保留 red**                           |
| 改了按钮忘同步 spinner 颜色                             | loading 圈与描边撞色不协调          | `CircularProgressIndicator(color: 同按钮色)`             |
| 保留个别"主操作 CTA"纯色填充                            | 用户仍投诉"还有纯色"                | 全转 OutlinedButton；层级靠**颜色 + 位置**，不靠填充 |
| helper 第一版写成`(BuildContext, {bool destructive})` | 只能二选一，无法表达多语义色        | 直接收`Color` 参数                                       |
| 改造范围蔓延到`IconButton`（纯图标）                  | 误伤，IconButton 本就不算纯色块     | 只改"填充式"容器/按钮                                      |

## 检查清单

- [ ] 无残留 `LinearGradient` / 饱和 `color` 填充的 icon 容器
- [ ] 无残留 `ElevatedButton(backgroundColor: Colors.X, foregroundColor: white)` / `FilledButton(backgroundColor: Colors.X)`
- [ ] 装饰元素统一主题色，功能按钮撞色
- [ ] 破坏性操作保留红色
- [ ] 全用 `withValues(alpha:)`，无 `withOpacity`
- [ ] helper 复用样式，调用处一眼看清功能色
- [ ] loading / spinner 颜色与所在按钮同步

## 项目内实战范例

- `lib/lab/demos/notion_image_host_demo.dart` — `_outlinedBtnStyle(Color color, {double borderWidth})` helper + 设置抽屉 UI
- `lib/lab/demos/api_test_demo.dart` — 早期应用范例