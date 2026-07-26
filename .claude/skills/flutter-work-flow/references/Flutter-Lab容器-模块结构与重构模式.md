# Flutter Lab 容器 — 模块结构与重构模式

> 何时读：改 `lib/screens/profile/lab/` 下任何文件（Lab 页 / 下拉收藏面板 / 游戏中心 / demo 卡片）、
> 或要给别的"重手势 + 重动画"页面做同类性能/结构优化时。
>
> 背景：2026-07 该目录从「lab_page.dart + 4 个 part 文件互相咬合」重构为 import 模块。
> 四个提交：ValueNotifier 双通道 → 手势收敛 → part 拆模块 → 共享件抽取。

---

## 一、当前目录结构（改代码前先对号入座）

```
lib/screens/profile/lab/
├── lab_page.dart            页面装配 + 动画驱动 + 双通道发布（~517 行，只做这三件事）
├── game_center_page.dart    游戏中心页（CustomScrollView + 分类过滤 + 自适应网格）
├── demo_detail_page.dart    DemoDetailPage —— 打开一个 DemoPage 的公共外壳（Lab/游戏中心共用）
├── demo_cover_image.dart    DemoCoverImage —— 封面图加载（缩略图缓存/本地/网络，共用）
├── reveal_item.dart         RevealItem —— 逐项错峰入场动画（节奏参数化，共用）
├── lab_perf_log.dart        kLabPanelPerfDebug 开关 + labPerfLog()
├── lab_panel/               下拉收藏面板全套
│   ├── const_lab_panel.dart          模块常量（色/圆角/时长/网格参数全在这）
│   ├── lab_panel_colors.dart         LabPanelColors（ColorScheme 推导，亮暗自适应）
│   ├── lab_panel_state_machine.dart  状态机+metrics（纯逻辑，零 widget，可单测）
│   ├── lab_panel_gesture.dart        LabPanelGestureCoordinator（三路输入收敛）
│   ├── lab_panel_content.dart        面板内容（标题条/收藏格子/删除区）
│   ├── lab_panel_handle.dart         PanelHandle（把手，自订阅 progress）
│   └── lab_panel_painters.dart       PanelSurfacePainter
├── demo_grid/
│   ├── demo_card.dart                DemoCard + 长按背景设置 sheet
│   └── demo_reveal_grid.dart         DemoScrollRevealGrid（2 列固定网格）
├── game_center/
│   ├── const_game_center.dart        slug→GameMeta 登记表 + 分类 + 布局常量
│   ├── game_center_artwork.dart      GameArtwork 程序化封面
│   └── game_center_cards.dart        精选大卡/网格卡/分类 chip/收藏星标
└── providers/
    └── lab_card_provider.dart        收藏 + 自定义背景（SharedPreferences，key=demo.title）
```

改动路标：
- 加游戏 → 只动 `const_game_center.dart`（kGameMeta 加一条）+ demo override `type => DemoType.game`
- 调面板视觉参数 → 只动 `const_lab_panel.dart`
- 改面板开合手感（阈值/速度）→ `lab_panel_state_machine.dart` 的 `LabPullPanelMetrics`
- 改手势路径 → `lab_panel_gesture.dart`，不要把逻辑写回 lab_page

## 二、双通道发布模式（重手势页面的性能骨架）

问题：拖拽/动画每帧 `setState(() {})` → 整页（AppBar+网格+面板）全部重建，慢帧。

解法——把状态拆成两条通道：

```dart
// 连续量：每帧变，只走 notifier，不 setState
final ValueNotifier<double> _progressNotifier = ValueNotifier(0.0);
// 离散量：状态机 state 真的换了才 setState
LabPullPanelState _publishedState = LabPullPanelState.collapsed;

void _publish() {                 // 所有「改完状态机就刷新」的唯一出口
  if (!mounted) return;
  _progressNotifier.value = _sm.progress;
  if (_publishedState != _sm.state) {
    _publishedState = _sm.state;
    setState(() {});
  }
}
```

配套两个关键点，缺一不可：

1. **订阅端各自 `ValueListenableBuilder`**：AppBar 折叠、主内容位移、面板高度、内容变换、把手 —— 每帧只重建这些轻量包装。
2. **重活 widget 实例只造一次**：demo 网格 / 面板背景 / 面板内容在 build 里先建好，
   每帧把**同一个实例**传进 builder —— `Element.update` 遇 `identical(new, old)` 直接短路，子树不进 build。

派生量（readyToOpen / closeProgress）是 progress 的纯函数 → 订阅端自己算，不要逐帧当 prop 传。

## 三、手势收敛模式

重手势页面常有 N 条输入路径（本例三条：Listener 指针流 / ScrollNotification / handle GestureDetector）。
**全部收进一个 Coordinator 类**，页面 State 只留两个出口：`onProgressChanged`（发布）+ `onAction`（播动画）。

- 速度**必须用 `VelocityTracker`**（`package:flutter/gestures.dart`），不要 `DateTime.now()` 手算
  dy/dt —— 相邻两事件的抖动会放大成假速度；VelocityTracker 最小二乘拟合，与系统手势同口径。
- **必须处理 `onPointerCancel`**：指针被来电/通知栏抢走时给 dragging 状态收尾，否则面板卡在中间进度。
- Coordinator 依赖用函数注入（`viewportHeight: () => _lastViewportHeight`），保持零 widget 依赖可单测。

## 四、part → import 模块的拆法

part 链的代价：所有 part 共享 library 私有名，互相咬合 → 任何复用都要先把私有类"提升"为公共类。
（DemoDetailPage、DemoCoverImage、RevealItem 都是这么被迫提升出来的。）

拆分套路：
1. 按职责分目录（面板一套 / 网格一套），每文件顶部写职责注释
2. 跨文件使用的类提升为公共名（`_DemoCard`→`DemoCard`）；State 类保持私有
3. library 级全局函数/开关（如 `_labPerfLog`）落成独立小文件
4. 常量层（const_xxx.dart）随模块走，公共常量放共享件自身文件里
5. 拆完 `dart format` 整目录 + `dart analyze` 必须 0 error 才提交

## 五、真踩过的坑

| 坑 | 现象 | 结论 |
|---|---|---|
| 每帧 setState 整页重建 | 拖面板慢帧（作者留了 perf 日志开关自证） | 双通道 + identical 短路（第二节） |
| DateTime.now() 手算速度 | 抬手瞬间抖动 → 假速度误触发开/合 | VelocityTracker |
| 无 onPointerCancel | 来电/通知栏抢指针 → 面板卡中间 | 三路输入都要有 cancel 收尾 |
| itemBuilder 里 firstWhere 扫全表 | 收藏 8 个 × demo 40 个 = 每帧 320 次比较 | build 前建 title→demo Map，didUpdateWidget 跟随重建 |
| 别名 slug 重复渲染 | 一个 demo 实例挂多个 slug，getAll() 返回全部 → 列表重复卡片 | UI 渲染前按实例去重 `where(seen.add)`；路由查询才用全量 |
| 收藏 key 用中文 title | 改 demo 标题 = 用户收藏/背景静默丢失 | 已知债务（P0#1 未做）：迁 slug 需一次性数据迁移，动 provider 前先看这条 |
| 面板高度想改 Align 裁剪省事 | 把手跟不上面板上边缘，被切掉 | 面板必须 Positioned + height 真收缩 |

## 六、验收清单（动过 lab/ 后跑一遍）

- [ ] `dart analyze lib` 0 error（孤儿文件也会被扫到）
- [ ] 真机链路：下拉展开 → 把手收起 → 中途松手回弹 → 收藏格子长按排序/拖删
- [ ] 拖拽全程 demo 网格不重建（打开 `kLabPanelPerfDebug` 看慢帧日志）
- [ ] 游戏中心收藏与 Lab 面板收藏同源（同一个 LabCardProvider）
