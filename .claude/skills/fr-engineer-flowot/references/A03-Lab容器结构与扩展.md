---
name: A03-Lab容器结构与扩展
description: FR Lab registry、DemoPage、收藏面板和游戏中心的真实扩展点与性能/手势模式。修改 Lab 层、添加 Demo 或遇到面板交互性能问题时读取。
---

# A03 — Lab 容器与模块扩展

> **适用范围**：仅适用于 FR 的 Lab/UI 容器。当前目录、注册项会随代码演进；动手前以本文的真实代码入口与 `lib/lab/lab_bootstrap.dart` 注册表复核，不把数量/行数快照当契约。

## 1. 先确定改动落点

| 改动目标 | 当前实现入口 | 下一步 |
|---|---|---|
| DemoPage/slug/type/session scope | `lib/lab/lab_container.dart` | 阅读 `DemoPage` 与 `DemoRegistry`；新增 demo 后在 `lab_bootstrap.dart` 注册 |
| Lab 列表、收藏面板装配 | `lib/screens/containers/lab_container.dart` | 找对应 builder/Provider，确认重建边界 |
| 下拉收藏面板状态/metrics | `lib/screens/profile/lab/lab_panel/lab_panel_state_machine.dart` | 纯状态转移尽量在此测试，不把手势条件塞回页面 |
| 指针/滚动/把手的输入协调 | `lib/screens/profile/lab/lab_panel/lab_panel_gesture.dart` | 修改某一路输入时核对其他路径及 cancel 收尾 |
| Demo 网格与卡片 | `lib/screens/profile/lab/demo_grid/` | 检查 instance 去重、item builder 与重绘范围 |
| 游戏中心 | `lib/screens/containers/game_center_container.dart`、`game_center/` | 新游戏必须同步 kGameMeta、Demo 注册和 kGameCenterCatalog；发布目录流程见 [[A05-游戏中心扩展]] |
| Demo 详情页/共享封面 | `demo_detail_page.dart`、`demo_cover_image.dart` | Lab/游戏中心共用外壳，先复用现有组件 |

上述文件路径是当前入口导航，不表示目录下每个文件职责永不变化；修改前确认符号仍存在。

## 2. 新增 Lab Demo 工作流

1. 确认它确实属于 Lab Demo，而不是已有独立页面或 core 业务模块；先查 `lab_bootstrap.dart` 是否已有相近实现。
2. 在 `lib/lab/demos/` 实现 `DemoPage` 子类，明确 title、description、canonical ASCII `slug`、`DemoType` 和需要的 scope。
3. 在 `lib/lab/lab_bootstrap.dart` 注册一次；如要兼容旧 deep link，按 [[A06-Demo-Slug别名]] 注册旧 key 到同一实例。
4. 外部/多入口导航遵循 [[A01-fr路由注册与防腐蚀]]；新游戏另执行 [[A05-游戏中心扩展]] 的 catalog 和发布步骤。
5. 按 A08 对目录职责、布局、测试、analyze/codegen 和交付进行验证。

Demo 默认单文件，不以目录树整洁为由先拆文件。超过约 400 行**或已有独立职责/复用边界**时，才评估移至 `lib/lab/demos/<module>/`；阈值是评估信号而非机械规则。

## 3. Lab 面板性能模式

当前面板用纯状态机管理离散 panel state/metrics，通过 `ValueNotifier<double>` 发布连续拖动 progress；页面只有离散状态变化才 `setState`，各轻量 builder 订阅其所需值。

改动拖动/动画时：

- 先读 `lab_panel_state_machine.dart`、`lab_panel_gesture.dart` 和 `lab_page.dart` 的真实连接。
- 连续值不要触发无关整页重建；大网格、模糊背景等重绘负担需检查 repaint boundary / widget subtree。
- `Listener`、`ScrollNotification`、把手 GestureDetector 等并存输入必须集中协调；每个 pointer lifecycle 都有 cancel/end 收尾。
- 不在 builder 中反复全 registry 搜索或创建昂贵静态内容；先 profile/看已有 `labPerfLog` 再做优化。
- 修改交互后验证展开、半途松手、取消指针、快速重复操作、滚动及收藏管理。

## 4. 游戏中心注册约束

游戏中心的三份关键数据需要保持一致：

1. demo registry 中的 `DemoPage` 且 `type == DemoType.game`；
2. `kGameMeta` 中的 UI 分类/标签信息；
3. `kGameCenterCatalog` 中可供管理端与公开目录发布使用的 entry。

修改前看 `game_center_page.dart` 中当前断言和 `test/lab/game_center_catalog_test.dart`。加游戏时按 [[A05-游戏中心扩展]] 补 catalog、相关测试与公开目录发布；不要只改 UI 分类表。常规调色/封面视觉按 E 序列，资源上传按 F00/Fa 序列。

## 5. 真实问题排查闭环

| 症状 | 先查 | 修复与验证 |
|---|---|---|
| Demo 不出现在 Lab | bootstrap 注册、slug/type/scope 和 Lab filter | 补齐唯一注册和 metadata；运行相应 registry/slug test，再 analyze |
| 一个 demo 在 Lab/游戏中心重复 | `demoRegistry.getAll()` 的 alias 条目是否指向同一个实例、UI 是否按实例去重 | UI 用实例身份去重，registry 保留 alias 路由；测试主 key 和 alias resolve 同一对象 |
| 拖动期间整页掉帧 | `setState` 调用范围、ValueListenable 订阅树、阴影/blur 重绘 | 缩小重建范围并 profile；不得仅凭视觉猜测优化效果 |
| 面板在中途卡住 | `onPointerCancel` / scroll end / state machine reset | 补相应输入路径的 cleanup 和 widget/controller test |
| 新游戏管理端无封面入口 | `kGameCenterCatalog` 是否与 demo/`kGameMeta` 一致、是否发布最新目录 | 按 A05 更新目录并跑双向 catalog test；用户授权后再执行远端发布 |

## 边界

- 这一 ref 指导 Lab 容器与列表/面板；游戏规则、主题配色、远端资产、Hive 数据分别使用 C/E/F/D 序列。
- 具体路径或数值若与当前源码不一致，应更新此导航表与对应 SOP，不能把旧快照当成事实。
