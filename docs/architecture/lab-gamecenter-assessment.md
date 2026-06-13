# Lab / Demos 容器机制评估与游戏中心扩展方案

> 审阅版 | 生成日期：2026-06-14
>
> 结论先行：当前 `lab/demos` 注册阶段**只加载元数据、无性能风险**；真正的规模化风险在**渲染层**和**身份键复用**。游戏中心（`type` 字段 + 过滤 + 独立页面）可以低成本落地，但"自动注册"在 Flutter AOT 下必须退化成**编译期代码生成**。

---

## 1. 背景与目标

### 1.1 用户诉求

1. 在现有 `lab/demos` 容器机制上，为 `DemoPage` 增加一个 `type` 字段（例如 `util` / `tool` / `game`）。
2. 通过 `type` 过滤，使用同样的 IoC / 控制反转方式搭建一个**游戏中心**。
3. 希望实现某种程度的**自动注册**，避免每次新增 demo 都手动编辑中央注册文件。
4. 担心整体架构会导致**后期难以维护**或**大规模踩坑**。

### 1.2 评估方法

- **全量审计**：使用多个子代理并行阅读全部 33 个 demo 文件，验证其 `DemoPage` 构造函数与 `registerXxx()` 函数是否只做元数据注册，是否存在副作用。
- **性能审计**：阅读 `LabPage` 渲染链路（`lab_page.dart`、`components.dart`、`panel_content.dart` 等），识别随 demo 数量线性放大的性能风险。
- **多视角评估**：
  - **平台视角**：Flutter/Dart 是否支持真正的运行时"自动注册"。
  - **设计视角**：`type` 字段与游戏中心的最小干净设计。
  - **维护视角**：从 33 个 demo 增长到 100+ / 50+ 游戏时，哪些设计会率先失效。

---

## 2. 现状架构

### 2.1 注册链路

```
main.dart
  └─ bootstrapLab()
      └─ registerAllDemos()      // lib/lab/lab_bootstrap.dart
          └─ registerXxxDemo()   // 每个 demo 文件尾部
              └─ demoRegistry.register(XxxDemo())
```

- `DemoPage` 抽象类位于 `lib/lab/lab_container.dart:7`：
  ```dart
  abstract class DemoPage {
    String get title;
    String get description;
    Widget buildPage(BuildContext context);
    bool get preferFullScreen => false;
  }
  ```
- `DemoRegistry` 是一个单例，内部是 `Map<String, DemoPage>`，默认 key 为 `demo.title`（`lib/lab/lab_container.dart:24-27`）。
- 所有 demo 的 `registerXxx()` 都是形如 `demoRegistry.register(XxxDemo())` 的平凡调用。

### 2.2 消费链路

`LabPage` 同时消费注册表：
1. **主网格**：`_ScrollRevealGrid` 渲染 `demoRegistry.getAll()`，每个 demo 一个 `_DemoCard`。
2. **收藏面板**：`_LabPanelContent` 从 `getAll()` 中过滤出收藏项，显示为可拖拽快捷方式。
3. **详情页**：`_DemoDetailPage` 调用 `demo.buildPage(context)`。

### 2.3 当前已注册 demo 数量

33 个（见第 8 节审计明细）。

---

## 3. 审计结论：注册阶段完全安全

### 3.1 全量 demo 注册成本审计

4 个审计代理分组阅读了全部 33 个 `*_demo.dart` 文件，结论完全一致：

| 指标 | 结果 |
|------|------|
| `DemoPage` 构造函数是否有副作用 | **无**。所有构造函数都没有字段初始化做 IO / Timer / Provider / 静态重活。 |
| `registerXxx()` 是否只做注册 | **是**。全部只调 `demoRegistry.register(XxxDemo())`。 |
| 重活是否延迟到页面打开 | **是**。`Timer.periodic`、Rive 加载、`.init()`、`MethodChannel`、文件 IO、Provider 创建全部位于对应 Page widget 的 `initState` / `didChangeDependencies` / `build` 中。 |
| 全局结论 `premiseHolds` | **true × 4 组**。 |

> **用户前提成立**："初始化只是加载一些元数据"在当前代码库是事实，不是假设。

### 3.2 为什么 registration 不会随数量恶化

- 每个 `DemoPage` 子类实例是**无状态轻对象**（几个 getter 重写）。
- `buildPage` 返回 `const _XxxPage()` 或等价的惰性构造，**不会触发内部 `StatefulWidget` 的 `initState`**。
- 所以即使 demo 数量增长到 200，冷启动 `bootstrapLab()` 仍然只是 200 次简单对象分配。

---

## 4. 性能风险：真正需要担心的问题不在注册

注册阶段安全，但 `LabPage` 的**渲染路径**存在随 demo 数量线性放大的问题。

### 4.1 风险一：LabCardProvider 监听器扇出

`components.dart:28`：
```dart
_provider.addListener(_onProviderChanged);
```

`_DemoCard` 的每个实例在 `initState` 都给单例 `LabCardProvider` 加监听器。当：
- 某张卡片设置背景、
- 用户收藏/取消收藏、
- 拖拽排序完成、

`LabCardProvider` 都会 `notifyListeners()`，**所有已挂载的卡片都会重建**。

| demo 数量 | 一次收藏动作触发的卡片重建 |
|-----------|----------------------------|
| 33        | 33 次                      |
| 100       | 100 次                     |

### 4.2 风险二：拖拽面板时的全页重建

`lab_page.dart:194-205`：
```dart
void _onPointerMove(PointerMoveEvent event) {
  _trackVelocity(event.position.dy);
  if (_sm.state == LabPullPanelState.draggingMain && _lastViewportHeight > 0) {
    _sm.updateMainDrag(deltaDy: event.delta.dy, fullHeight: _lastViewportHeight);
    setState(() {});
  }
}
```

面板拖拽时约 60Hz 调用 `setState`，整个 `_LabPageState` 重建，导致：
- `demoRegistry.getAll()` 重新分配 `.entries.toList()`；
- 主网格和收藏面板一起参与重建；
- `_ScrollRevealGrid`、`_DemoCard` 大量参与。

### 4.3 风险三：冷启动图片预加载惊群

`_DemoCard.initState` 会 `_preloadImage()`，33 张卡同时发起文件 IO / `Image.network`。demo 翻倍后，首页首次打开会有明显 IO 尖峰。

### 4.4 风险四：onLoaded 忙等 + 背景序列化缺陷

`lib/screens/profile/lab/providers/lab_card_provider.dart:22-26`：
```dart
Future<void> get onLoaded async {
  while (!_isLoaded) {
    await Future.delayed(const Duration(milliseconds: 50));
  }
}
```

每张卡都轮询 50ms 等待加载。100 卡就是 100 个异步轮询。

此外背景序列化用手工 CSV（`split(',')` + `split(':')`），URL 里含 `:` 或 `,`（例如端口 `localhost:8080`、data URI）会被截断或损坏。

### 4.5 性能总结

| 场景 | 当前 33 demo | 100 demo | 建议修复优先级 |
|------|--------------|----------|----------------|
| 注册冷启动 | 安全 | 安全 | 无需处理 |
| 收藏/背景变更 → 全网格重建 | 已存在 | 显著 | **高** |
| 面板拖拽 → 全页 60Hz 重建 | 已存在 | 更卡 | **高** |
| 冷启动图片预加载惊群 | 轻微 | 明显 | 中 |
| onLoaded 轮询 | 轻微 | 浪费 | 中 |

---

## 5. "自动注册"：平台级硬约束与可行方案

### 5.1 核心结论：后端式自动注册在 Flutter 不可能

- Flutter AOT / release 构建**没有 `dart:mirrors`**。
- Dart 团队正在废弃 `dart:mirrors`（参考 `dart-lang/sdk#44489`），它仅在 VM/JIT 模式下存在。
- **没有任何包**能在 Flutter AOT 运行时"扫描并实例化所有实现 X 接口的类"。`injectable`、`kiwi`、`get_it` 全部都是**编译期代码生成**。

因此"自动注册"在 Flutter 里永远是：**代码生成器在 build 时 Emit 出一份注册列表**。我们要选的只是生成机制，不是"用不用生成"。

### 5.2 三种可行方案对比

| 方案 | 实现方式 | 优点 | 缺点 | 推荐度 |
|------|----------|------|------|--------|
| **(c) 手写 Dart 脚本** | `tools/gen_lab_bootstrap.dart` 扫描 `lib/lab/demos/*_demo.dart`，正则提取 `void register<Name>()`，重写 `lab_bootstrap.dart` | 零新依赖；~80 行；复用现有 build_runner 习惯；完全匹配当前自由函数契约 | 需要 pre-commit / CI guard 防止"忘跑生成"导致 demo 静默丢失 | **⭐ 推荐** |
| (b) `build_runner` + `source_gen` | 定义 `@labDemo` 注解，自定义 Generator | 标准路径；便于未来扩展元数据（分组、排序、feature flag） | 对当前需求过重：契约太简单，无需 AST 解析 | 可选 |
| (a) `injectable` / `get_it` | 使用 `@Injectable(as: DemoPage)` | 看起来"工业级" | 当前契约是"自由函数 + DemoPage 抽象类"，不是 get_it 构造函数注入；需要重写 33 个文件，改动大 | ❌ 不推荐 |
| 运行时扫描 | `Directory.listSync` + 反射 | Flutter AOT 不支持 | 不可行 | ❌ 不可能 |

### 5.3 推荐落地方案

写一个无外部依赖的 Dart 脚本 `tools/gen_lab_bootstrap.dart`：

1. 遍历 `lib/lab/demos/` 下所有 `*_demo.dart`。
2. 每个文件用正则提取 `void register(\w+)\(\)`。
3. 生成 `lib/lab/lab_bootstrap.dart`，顶部加 `// GENERATED CODE — run dart tools/gen_lab_bootstrap.dart`。
4. 配置 pre-commit hook 或 IDE Task 自动运行。
5. 加一个测试或 CI 断言：`demos/*_demo.dart 数量 == lab_bootstrap.dart 中 registerXxx() 调用数量`。

> 这套方案的前提是：当前每个 demo 文件都稳定包含一个 `void registerXxxDemo()` 函数。全量审计已确认这一点。

### 5.4 何时做

当前 33 个 demo、80 行的 `lab_bootstrap.dart` 仍可读；建议 **demo 数量超过 40 后再引入脚本**，因为脚本本身也有维护成本。如果你预计会持续增加游戏/demo，那么现在做也无妨。

---

## 6. 最危险的架构缺陷：demo.title 被复用为身份键

这是当前代码库**最大的踩坑点**，与游戏中心无关，但游戏中心会让它更快暴露。

### 6.1 问题：title 同时是 3 个系统的键

| 系统 | 键 | 代码位置 |
|------|----|----------|
| DemoRegistry Map | `demo.title` | `lib/lab/lab_container.dart:25` |
| 卡片背景 SharedPreferences | `demo.title` | `lib/screens/profile/lab/providers/lab_card_provider.dart:32` |
| 收藏 / 收藏排序 SharedPreferences | `demo.title` | 同上，`:36` / `:40` |

### 6.2 具体后果

1. **同名 demo 静默覆盖**：`register()` 默认 key = `title`，且**没有碰撞检查**。如果两个 demo 都叫 `"2048"`，后注册的会覆盖前者，`getAll()` 只剩一个，用户从网格里永远看不到另一个。代码：`lab_container.dart:24-27`。
2. **状态串台**：两个同名 demo 的背景、收藏状态会互相覆盖。
3. **重命名即数据丢失**：把 `title` 从 `"贪吃蛇"` 改成 `"经典贪吃蛇"`，所有用户保存的背景图和收藏全部变成孤儿，旧的 key 永远残留在 SharedPreferences 里。
4. **未来做 Game Center 必踩**：游戏标题常常重复或迭代（"2048"、"Flappy" 等），这个缺陷会频繁触发。

### 6.3 修复方案

给 `DemoPage` 增加稳定 opaque ID，并用它替代 `title` 作为所有内部键：

```dart
abstract class DemoPage {
  String get title;
  String get description;
  String get id;               // 新增：稳定身份键
  Widget buildPage(BuildContext context);
  bool get preferFullScreen => false;
}

// 默认实现：用类名，通常唯一且不会随文案变化
String get id => runtimeType.toString();
```

- `DemoRegistry` 默认 key 改为 `demo.id`。
- `register()` 增加 debug assert：`assert(!_demos.containsKey(demoKey))`。
- `LabCardProvider` 的 background/favorite key 改为 `demo.id`。
- `_loadData()` 中做一次 legacy 迁移：把旧 title-keyed 条目按已知映射搬到 id-keyed。

这是 **P0 级别**的修复，应该在游戏中心之前就完成。

---

## 7. 游戏中心方案：最小改动、零新单例

### 7.1 设计原则

- **非破坏性**：不改现有 demo 的构造签名。
- **不重构注册表**：`DemoRegistry` 保持最小（register / get / getAll / count）。
- **不新增单例**：复用 `demoRegistry` 和 `LabCardProvider`。
- **不塞入 LabPage 状态机**：LabPage 的下拉面板已经是一个 500 行的复杂状态机，游戏中心应作为独立页面。

### 7.2 具体改动

#### 7.2.1 给 `DemoPage` 加 `type` 字段

在 `lib/lab/lab_container.dart`：

```dart
enum DemoType { util, tool, game }

abstract class DemoPage {
  String get title;
  String get description;
  DemoType get type => DemoType.util;   // 默认工具/通用
  // ... id / buildPage / preferFullScreen
}

extension DemoTypeFilter on Iterable<MapEntry<String, DemoPage>> {
  List<MapEntry<String, DemoPage>> whereType(DemoType t) =>
      where((e) => e.value.type == t).toList();
}
```

**为什么用 getter 而非构造函数参数**：当前 `preferFullScreen` 已经使用这种模式，所有 30+ demo 都无需重写构造签名。只有两个游戏需要覆盖：

```dart
class SnakeGameDemo extends DemoPage {
  @override DemoType get type => DemoType.game;
  // ...
}

class Game2048Demo extends DemoPage {
  @override DemoType get type => DemoType.game;
  // ...
}
```

#### 7.2.2 Game Center 独立页面

新建 `lib/screens/profile/game/game_center_page.dart`，声明为：

```dart
part of '../../lab/lab_page.dart';
```

原因：`_ScrollRevealGrid`、`_DemoCard`、`_DemoDetailPage` 都是 `lab_page.dart` 的私有 `part` widget，通过 `part of` 可以直接复用，避免大规模重构。

页面内部：

```dart
class GameCenterPage extends StatelessWidget {
  const GameCenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final games = demoRegistry.getAll().whereType(DemoType.game);
    return Scaffold(
      appBar: AppBar(title: const Text('游戏中心')),
      body: _ScrollRevealGrid(
        demos: games,
        controller: ScrollController(),
        onDemoTap: (demo) => _openDemoPage(context, demo),
        physics: const BouncingScrollPhysics(),
      ),
    );
  }
}
```

#### 7.2.3 入口

在 `lib/screens/profile/profile_page.dart` 的菜单区域新增一张卡片（与"开发者实验室"并列），点击进入 `GameCenterPage()`。

### 7.3 改动文件清单

| 文件 | 改动 |
|------|------|
| `lib/lab/lab_container.dart` | 加 `DemoType` enum、默认 `type` getter、`whereType` extension；可选：加 `id` getter（P0 建议） |
| `lib/lab/demos/snake_game_demo.dart` | override `type => DemoType.game` |
| `lib/lab/demos/game_2048_demo.dart` | override `type => DemoType.game` |
| `lib/screens/profile/game/game_center_page.dart` | 新增独立页面（`part of lab_page.dart`） |
| `lib/screens/profile/profile_page.dart` | 新增"游戏中心"菜单入口 |
| `lib/lab/lab_container.dart`（P0） | `register()` 去重 assert、key 改为 id |
| `lib/screens/profile/lab/providers/lab_card_provider.dart`（P0） | prefs key 改为 id，legacy 迁移 |

> 如果只做游戏中心 MVP，只需要前 5 个文件；如果加上 P0 id 修复，共 7 个文件。

### 7.4 耦合陷阱说明

1. **LabCardProvider 全局共享是 feature，不是 bug**：同一个 `DemoPage` 对象在 Lab 网格和 Game Center 显示，背景/收藏状态自然共享。不要为 Game Center 新建 provider。
2. **Schema 深链接限制**：`fr://lab/demo/Key` 的 schema navigator 会 `popUntil` 到 `/lab` 再 push。如果游戏内部再通过 schema 打开另一个 demo，用户会被带回 LabPage 而非 GameCenterPage。当前 MVP 不触发，后续需注意 `lib/core/schema/schema_navigator.dart`。

---

## 8. 建议的行动路线图

| 阶段 | 优先级 | 内容 | 收益 | 风险 |
|------|--------|------|------|------|
| **P0** | 最高 | 给 `DemoPage` 加稳定 `id`；`DemoRegistry` key 与 `LabCardProvider` prefs key 全部迁移到 id；`register()` 加去重 assert；`_DemoDetailPage` 包 try/catch + ErrorWidget | 消除同名覆盖、重命名丢数据、单 demo 崩溃炸导航 | 涉及 SharedPreferences 迁移，需要测试 |
| **P1** | 高 | 落地 `DemoType` + `whereType` + `GameCenterPage` + 菜单入口 | 快速实现游戏中心，新增约 5 个文件 | 几乎无风险 |
| **P2** | 中 | 写 `tools/gen_lab_bootstrap.dart` 自动生成注册表；修复 listener 扇出、拖拽重建、onLoaded 忙等 | 支撑 100+ demo，提升性能 | 需要 CI/hook 兜底 |

**推荐执行顺序**：P0 → P1 → P2。

原因：
- P0 不依赖游戏中心，且越早做，未来重命名 demo 或新增游戏时越安全。
- P1 独立、低风险，做完即可看到游戏中心。
- P2 是规模化后的锦上添花，可在 demo 超过 40 个时再启动。

---

## 9. 附录 A：33 个 Demo 注册成本审计明细

以下结论来自 4 个独立审计代理并行阅读后的汇总。所有 demo 的 `DemoPage` 构造函数都是**trivial**，`registerXxx()` 都**只注册**。

| Demo 文件 | 重活实际发生位置 | 备注 |
|-----------|------------------|------|
| `api_test_demo.dart` | `_ApiTestPageState.initState` | 含 `ApkDownloadManager` 初始化 |
| `body_map_demo.dart` | 无 | 纯展示 |
| `bottom_bar_demo.dart` | `_LegacyBottomBarState.initState` | `AnimationController` |
| `calendar_demo.dart` | 无 | `Consumer<LabCalendarProvider>` 在 build 时解析 |
| `clock_demo.dart` | `_ClockDemoPageState.initState` | `Timer.periodic`、动画、传感器、SharedPreferences |
| `color_palette_demo.dart` | 无 | 纯展示 |
| `demo_laboratory_demo.dart` | `_DemoLaboratoryPageState` lazy final 字段 | Rive `FileLoader` 在导航后构造 |
| `doubletime_demo.dart` | 无 | 重活下沉到 `core/doubletime` |
| `free_canvas_demo.dart` | 无 | 图片/文件 IO 在 State 方法内 |
| `gallery_demo.dart` | 无 | 纯展示入口 |
| `github_demo.dart` | 无 | SharedPreferences 在 `_GithubDemoShellState.initState` |
| `grid_dashboard_demo.dart` | 无 | 数据静态 |
| `line_demo.dart` | 无 | 纯展示 |
| `localnet_demo.dart` | 无 | 纯展示 |
| `network_demo.dart` | 无 | 子 tab 内按需初始化 |
| `novel_reader_demo.dart` | 无 | 纯展示 |
| `overlay_demo.dart` | `_OverlayDemoPageState.initState` | `_initService` |
| `pigment_palette_demo.dart` | `_PigmentPaletteDemoPageState.initState` | `_service.init()` |
| `qr_demo.dart` | `_QrPageState.initState` | 相机/平台初始化 |
| `rive_data_bind_demo.dart` | `_RiveDataBindPageState` | lazy final `FileLoader`，导航后构造 |
| `rive_pendulum_demo.dart` | `_RivePendulumPageState` | lazy final `FileLoader` |
| `schema_demo.dart` | `_SchemaDemoPageState.initState` | 控制器初始化 |
| `sensor_demo.dart` | `_SensorPageState.initState` | 打开传感器流 |
| `set_tracker_demo.dart` | `_SetTrackerPageState.initState` | `AnimationControllers` |
| `storage_analyze_demo.dart` | `_StorageAnalyzePageState` | post-frame 加载存储 |
| `torch_demo.dart` | `_TorchPageState.initState` | 平台调用、亮度、动画 |
| `volume_decay_demo.dart` | `_VolumeDecayPageState.initState` | MethodChannel |
| `web_bookmark_demo.dart` | `_WebBookmarkPageState.build` | `ChangeNotifierProvider` 在 build 时创建，仍非注册期 |
| `word_drag_demo.dart` | 无 | 重活下沉到 `core/word_drag` |
| `game_2048_demo.dart` | `_Game2048PageState.initState` | `_initGame()` |
| `snake_game_demo.dart` | `_SnakeGamePageState.initState` | `Timer.periodic` |
| `crash_log_demo.dart` | `_CrashLogDemoPageState.initState` | MethodChannel |
| `block_editor_demo.dart` | `_BlockEditorDemoState.didChangeDependencies` | `EditorState` 创建与初始化 |

> 共同模式：所有"重活"都被约束在导航后的 Page widget 生命周期内；`DemoPage` 自身只是元数据信封。

---

## 10. 附录 B：关键代码引用

- `DemoPage` 抽象类：`lib/lab/lab_container.dart:7-14`
- `DemoRegistry.register()`：`lib/lab/lab_container.dart:24-27`
- 手动注册表：`lib/lab/lab_bootstrap.dart:5-74`
- 全局 bootstrap：`lib/main.dart:38`
- LabPage 主网格与详情页：`lib/screens/profile/lab/lab_page.dart` / `lab_page/components.dart`
- LabCardProvider 单例与 prefs key：`lib/screens/profile/lab/providers/lab_card_provider.dart:5-36`
- Schema navigator popUntil：`lib/core/schema/schema_navigator.dart:140-143`

---

## 11. 决策待确认项

请审阅后确认：

1. **是否先落地 P0（id 身份键修复）**？这是数据迁移类改动，需要一次兼容旧数据的迁移逻辑。
2. **是否同时落地 P1（游戏中心 MVP）**？还是先看 P0 效果再决定？
3. **报告中的"自动注册"方案是否采纳脚本生成方案（`tools/gen_lab_bootstrap.dart`）**？还是暂时保持手动？
4. 是否希望我据此报告继续下一步实现？
