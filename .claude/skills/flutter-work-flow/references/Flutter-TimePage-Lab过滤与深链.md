# Flutter-TimePage — Lab 过滤与桌面 widget 深链

> ref：Lab 列表中 timePage demo 的过滤、`fr://lab/demo/<slug>` 路由可达性、Desktop widget 深链。**先读 `Flutter-TimePage-Focus时间模块设计` § 2-3 再看本 ref**。

## 触发场景

> 关键词：Lab 列表漏 timePage demo / 桌面 widget 点不到 clock / 多别名 demo 重复卡 / `fr://lab/demo/<slug>` 路由失败 / `excludeGames` 行为异常 / `demoRegistry.getBySlug` 返回 null。

跨域坑：以上任何一个 bug 都涉及 `lib/screens/profile/lab/lab_page.dart` + `lib/lab/lab_container.dart` + `lib/core/schema/handlers/lab_demo_handler.dart` 三个文件联动。

## 4 个不变量（错过一个就翻车）

| 不变量 | 违反症状 | 复现 |
| --- | --- | --- |
| **A.** `timePage` demo 必须从 Lab 列表消失 | 用户在中间 Time tab 点过 clock 后去 Lab 仍能找到它 → 体验割裂 | 打开 Lab 列表看是否见到时钟 / 日历 / 节拍器 |
| **B.** `fr://lab/demo/<slug>` 路由必须可达（含 timePage demo） | 桌面 widget 点击「clock widget」无反应 | Android Launcher 长按主屏 → 添加 widget → 跳失败 |
| **C.** `demoRegistry` 双索引（slug + title）不被破坏 | slug 改名后 widget / 旧 fr link 全断 | flutter test `demo_slug_test.dart` 红灯 |
| **D.** Lab 去重按 `DemoPage` 实例而非 slug | `rive-demo` 的 4 个别名 slug 在 Lab 出现 4 张重复卡 | 打开 Lab 列表扫一眼有无重复 |

**重要**：timePage demo 不动 Lab 过滤的运行时路径，只动 `_demos` 初始化的过滤逻辑。删除过滤会把 timePage demo 也放进 Lab。

## Lab 列表过滤机制（`lib/screens/profile/lab/lab_page.dart`）

```dart
// _demos 初始化（约 88 行）
final all = demoRegistry.getAll().where((e) => !e.value.timePage);   // ← 不变量 A
_demos = (widget.excludeGames
        ? all.where((e) => e.value.type != DemoType.game)            // ← excludeGames 联动
        : all)
    .where(seen.add)                                                  // ← 不变量 D (按 DemoPage 实例)
    .toList();
```

**顺序铁律**：`!timePage` 必须最先，否则 `excludeGames==false` 的路径可能漏 timePage demo。`seen.add` 在最后做去重——按 `DemoPage` 实例（不是 slug），保证别名 slug 只显示一次。

## `fr://lab/demo/<slug>` 路由可达性（不变量 B）

路由 handler 位置：`lib/core/schema/handlers/lab_demo_handler.dart`

```dart
class LabDemoHandler extends FrRouteHandler {
  static const _prefix = 'lab/demo/';

  @override
  Widget build(BuildContext context, FrRouteMatch match) {
    final auth = match.authority;
    if (!auth.startsWith(_prefix) || auth == _prefix.substring(0, _prefix.length - 1)) {
      return _NotFoundPage(message: '非法 lab demo 路由: $auth');
    }
    final demoKey = auth.substring(_prefix.length);
    final demo = demoRegistry.get(demoKey);  // ← 这里查 demoRegistry.get(slug|title)
    if (demo == null) {
      return _NotFoundPage(message: '未找到 Demo: $demoKey');
    }
    return _DemoDetailPage(demo: demo);
  }
}
```

**关键**：
- `demoRegistry.get(demoKey)` 双索引查（slug 优先，title 兜底）—— **不动 timePage 判断**。
- 路由不走 `timePage` 过滤，所以 timePage demo 路由可达性**自动满足**不变量 B。
- 桌面 widget 深链 (`main.dart` 的 MethodChannel handler) → `fr://lab/demo/<slug>` → 命中 `_prefix` → `getBySlug` 查表 → push `DemoDetailPage`。

桌面 widget 入口（`main.dart`）：
```dart
'navigateToClock'    => 'fr://lab/demo/clock',
'navigateToCalendar' => 'fr://lab/demo/calendar',
```

这些 fr:// 字符串**硬编码**，改 slug 必须同步改 `main.dart` 这两行（属于 `Flutter-DemoPage-slug抽象化与别名机制` ref 范畴）。

## 添加新 timePage demo 后必须做的不变验证

```bash
# 不变量 A: Lab 列表应该见不到新 demo
grep -rn "slug.*<new>" lib/screens/profile/lab/lab_page.dart   # 应该出现: 全局查询过滤掉它
adb shell am start -a android.intent.action.VIEW -d "fr://lab/demo/<new>"   # 路由可达

# 不变量 C: 双索引测试
flutter test test/lab/demo_slug_test.dart

# 不变量 D: 别名去重（如果新 demo 有别名）
flutter test test/lab/demo_slug_test.dart   # 看「Rive 4 个 slug 合一 demo」断言
```

## 修改 Lab 列表过滤的边界

| 允许的修改 | 禁止的修改 |
| --- | --- |
| 加 `timePage` 反向豁免（如 `_hiddenFromLab: false`） | 改 `excludeGames` 语义（如让它拦截 timePage demo） |
| 改去重顺序（先按 type 再按 seen） | 把 `seen.add` 改成按 slug 去重（破不变量 D） |
| 改排序方式 | 把过滤改成 lazy builder（缓存丢一个 bug 难调） |
| 加排序字段如 `sortBy = .title` | 给 Lab panel 加新手势（参考 `Flutter-Lab容器-模块结构与重构模式` ref） |

## 错误案例（沉淀）

### [2026-07-29] c0039ae8 Lab 过滤初次集成

**坑**：第一次集成 `timePage` 过滤时把过滤写成 `e.value.type != DemoType.time`（假设新加 enum 值）。

**根因**：与 `DemoType.game` 误平行——以为 time 也要新 enum 值。但 task 4 改用 `bool get timePage` 字段（与 type 正交），**改完测试才反应过来**。

**正确做法**：过滤写 `!e.value.timePage`（bool 字段判断），**不要新增 `DemoType.time` enum 值**。如果哪天业务需求演化让 time 必须有子类（如 timeTimer / timePlanner），再加 enum 值并保留 `timePage: true` 字段做兼容。

## 自检清单

完成后 grep 这几条：

```bash
grep -rn "where.*timePage" lib/screens/profile/lab/lab_page.dart   # Lab 过滤还在
grep -rn "filterByTimePage" lib/                                   # 还在用扩展（不要 inlined）
grep -rn "fr://lab/demo/clock" lib/main.dart                       # 桌面 widget 链可达
grep -rn "timePage" lib/core/schema/handlers/lab_demo_handler.dart  # handler 不查 timePage（合理）
flutter test test/lab/demo_slug_test.dart && echo OK
```

`lab_demo_handler.dart` **不**应出现 `timePage` grep 命中——路由不该感知 timePage 标记（timePage 是 Lab 列表层的 UI 关注点）。
