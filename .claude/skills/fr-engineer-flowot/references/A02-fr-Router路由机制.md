---
name: A02-fr-Router路由机制
description: 新增 fr:// 路由 handler、排查跳转失败或跳错页、写路由测试时读——FrUri authority 解析、最长前缀匹配、中文 URL 防御、CLEAR_TOP 防重复 push 的操作 SOP 与陷阱决策表。
---

# A02 — fr:// Router 路由机制（SOP）

> **何时读**：新增 `fr://` 路由 handler、排查「点了链接没反应 / 跳错页」、给路由系统写或改测试、重构 push/导航链路时。机制背景 30 秒在 §1，新增 handler 走 §2 工作流，出问题先查 §3 陷阱决策表。

## 1. 机制 30 秒

- 单注册中心 + 强类型 handler，代码在 `lib/core/schema/`：`fr_uri.dart`（解析）/ `fr_route.dart`（条目）/ `fr_route_handler.dart`（基类 + FrRouteMatch）/ `fr_router.dart`（单例注册中心）/ `fr_navigator.dart`（push 封装）/ `bootstrap_routes.dart`（集中注册）/ `handlers/*.dart`。
- 3 个入口（文本链接 / MethodChannel / 内部代码）全部收口到 `FrNavigator.handle(context, url)`：resolve → handler.build → CLEAR_TOP 防重 → push。
- authority = `'?'` 前整段（可含 `/`），路由 key 即 authority；最长前缀 + slash 边界匹配。

```text
文本: SchemaText.onLinkTap ────┐
MethodChannel: 翻译表 ─────────┼→ FrNavigator.handle → resolve → build → CLEAR_TOP → push
内部代码: FrNavigator.handle ──┘         失败: SnackBar + debugPrint
```

## 2. 新增一个路由 handler（工作流）

1. 新建 `lib/core/schema/handlers/<name>_handler.dart`，继承 `FrRouteHandler`，`build` 里用 `match.queryBool / queryString / pathSegment` 取参，不要自己拆 query：

```dart
/// fr://notion/image-host?autocapture={true|false}
class NotionImageHostHandler extends FrRouteHandler {
  const NotionImageHostHandler();

  @override
  Widget build(BuildContext context, FrRouteMatch match) {
    final autocapture = match.queryBool('autocapture');
    return NotionImageHostDeepLinkPage(autocapture: autocapture);
  }
}
```

2. 在 `bootstrap_routes.dart` 的 `registerAllFrRoutes()` 注册。key 用 authority 全段，支持嵌套命名空间（`lab` / `lab/demo` / `lab/demo/recorder` 各自注册不同 handler）。
3. MethodChannel 入口（仅原生反注册跳转需要）：在 `lib/app_lifecycle/fr_method_channel_translator.dart` 翻译表加一行 switch case，**不进 main.dart**；query 参数序列化进 URL，handler 端 `queryBool` 解析：

| call.method | 翻译为 |
|---|---|
| `navigateToLab` | `fr://lab` |
| `navigateToClock` | `fr://lab/demo/clock` |
| `navigateToTimetable` | `fr://timetable` |
| `navigateToNotionImage` | `fr://notion/image-host?autocapture=${(call.arguments as bool?) ?? false}` |

4. demo 页 URL key 用 ASCII slug，中文 title 仅作显示（陷阱 3）；新 demo slug 落法见 [[A06-Demo-Slug别名]]。
5. 补测试（断言规范见陷阱 4），过验证出口。

FrRouteMatch 工具方法（handler 侧取参唯一入口）：

```dart
String? queryString(String key) => query[key];

// queryBool 接受 'true'/'1'，其他值返回 defaultValue
bool queryBool(String key, {bool defaultValue = false}) {
  final v = query[key];
  if (v == null) return defaultValue;
  return v == 'true' || v == '1';
}

// pathSegment 拆 path 按 '/'，越界抛 RangeError
String pathSegment(int index) { /* ... */ }
```

## 3. 陷阱决策表（出问题先查这里）

### 陷阱 1：FrUri 拆 host 还是 authority —— 嵌套路由最深坑

| URL | 错误拆法（host = 第一个 `/` 前） | 正确拆法（authority 整段 + path） |
|---|---|---|
| `fr://lab` | host=`lab` ✅ | authority=`lab` ✅ |
| `fr://lab/demo/clock` | host=`lab` → 全部路由到 LabIndexHandler ❌ | authority=`lab/demo/clock` ✅ |

正确实现（`fr_uri.dart`）：authority = `'?'` 前整段保留；path = authority 内第一个 `'/'` 后的部分（decode 后）。**route key 永远用 authority 整段**，不是 host 单段——host 是单段字符串，表达不了 `lab/demo` 嵌套命名空间。

### 陷阱 2：前缀匹配必须带 slash 边界

route key 有长有短（`lab`、`lab/demo`、`notion/image-host`），不能用 `Map[key]` 直查，也不能裸 `startsWith`：

```dart
FrRouteHandler? findHandler(String authority) {
  // 按 key 长度降序，保证最长前缀优先（lab/demo 优先于 lab）
  final sortedKeys = _routes.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final key in sortedKeys) {
    if (authority == key) return _routes[key]!.handler;
    // 前缀匹配必须以 '/' 分隔，防 'labfoo' 误命中 'lab'
    if (authority.startsWith('$key/')) return _routes[key]!.handler;
  }
  return null;
}
```

| 输入 | 无边界检查 | 有边界检查 |
|---|---|---|
| `fr://lab` | ✅ 命中 `lab` | ✅ 命中 `lab` |
| `fr://lab/demo/clock` | ✅ 命中 `lab/demo` | ✅ 命中 `lab/demo` |
| `fr://labfoo` | ❌ 误命中 `lab` | ✅ 返回 null（`lab/` 不匹配） |

### 陷阱 3：中文 URL 崩溃 —— decodeComponent 只吃 percent-encoding

生产 bug 教训：所有含中文的 `fr://` URL 跳转崩溃（用户报「lab/demos 无法跳转」），藏在 41 个绿测试里。

- 根因：`Uri.decodeComponent` 期望 percent-encoded 输入（`%E6%97%B6%E9%92%9F`）；喂原始中文（`时钟`）抛 `ArgumentError: Illegal percent encoding in URI`。
- 定位信号：纯英文 URL 全好、含中文全崩（`FrNavigator` 静默失败 → 点击无反应）。
- 修复双保险：
  1. `safeDecode` 防御——无 `%` 直接返回原串；decode 抛错兜底返回原串；
  2. ASCII slug 规范根治——URL key 用英文 slug（`fr://lab/demo/clock`），中文仅显示文字；历史 slug 走 `demoRegistry.register(demo, key: alias)` 别名兼容（[[A06-Demo-Slug别名]]）。
- 测试教训：测试用编码形式、生产用原始中文，两条路径不重合——**路由测试必须覆盖原始中文输入**：

```dart
test('原始中文 URL 不崩', () {
  expect(FrUri.tryParse('fr://lab/demo/时钟'), isNotNull);
  expect(FrUri.tryParse('fr://lab/demo/时钟')!.authority, 'lab/demo/时钟');
});
```

### 陷阱 4：测试只断言非 null = bug 藏身处

本次 critical bug 藏在 Task 1–9 全绿的原因：测试只写了 `expect(match, isNotNull)`——解析成功但命中的是错的 handler。

```dart
// ❌ 危险：只断言非 null，嵌套层级错位时测试全绿功能全错
expect(match, isNotNull);

// ✅ 断言具体 handler 类型 + 反向断言不是父级 handler
expect(frRouter.findHandler(match!.authority), isA<LabDemoHandler>());
expect(frRouter.findHandler(match.authority), isNot(isA<LabIndexHandler>()));
```

## 4. CLEAR_TOP 防重复 push（重构易退化）

桌面 widget / onNewIntent / 文本链接任一入口反复触发 → 目标页被多次 push，返回手势要折叠多次才能退出。`FrNavigator.handle` 用 **CLEAR_TOP 语义**：目标路由已在栈中（任意深度）→ `popUntil` 提到栈顶不再 push；不在栈中 → 正常 push。

关键点：`Navigator` 公共 API 没有「列出当前栈」的方法，`popUntil` 是边查边 pop 的破坏性调用——非破坏性的「目标是否已在栈中」必须挂 `NavigatorObserver` 同步跟踪栈（`FrRouteStack`：didPush/didPop/didRemove/didReplace 维护列表，`containsName(name)` 查询；main.dart 注册 `navigatorObservers: [frRouteStack]`）。

```dart
final routeName = '/fr/${match.authority}/${match.path}';
if (frRouteStack.containsName(routeName)) {
  // 已在栈中 → 把它上面的页面全部 pop，提到栈顶；route.isFirst 是保险
  nav.popUntil((route) => route.settings.name == routeName || route.isFirst);
  return;  // 不再 push
}
nav.push(MaterialPageRoute(
  settings: RouteSettings(name: routeName),
  builder: (_) => target,
));
```

旧实现为什么不够：只用 `popUntil` 谓词立即返回 true 探查**栈顶**一个 route——交替点击 widget 时（`[Main, Clock]` → `[Main, Clock, Calendar]` → 再点时钟）栈顶是 Calendar ≠ Clock → 又 push → 栈无限累加，返回键在重复页之间循环。去重范围必须覆盖**全栈**而非仅栈顶。

两条教训：

1. 防重复 push 是隐性合约，单元测试很难覆盖（需 widget 测试模拟多次 MethodCall），code review 要专门检查 push 路径的去重逻辑。
2. 去重判断范围覆盖全栈，否则「交替点击 / 嵌套导航」绕过去重。

## 5. 错误处理矩阵

| 错误 | 表现 |
|---|---|
| scheme 非 `fr://` | debugPrint + 静默返回 |
| 找不到 authority | debugPrint + SnackBar「未知路由」 |
| handler 返回 null Widget | 静默 debugPrint（防御） |
| handler 抛异常 | SnackBar 显示 e.message + debugPrint stacktrace |
| context.mounted=false | 跳过 push，记录日志 |
| NavigatorState 为 null | debugPrint + 静默返回 |

## 验证出口

- `flutter test test/core/schema/` —— 41 个 case 全绿；新增/改动路由同步补三类断言：具体 handler 类型断言（陷阱 4）+ `fr://labfoo` 边界 case（陷阱 2）+ 原始中文 URL case（陷阱 3）。
- `flutter analyze lib/core/schema lib/app_lifecycle` → 0 error。
- 涉及原生入口（widget / onNewIntent）或 main.dart 接线的改动：[[A00-FR模块开发路由]] 动线收尾（build apk + CI 闸门）。

## 边界

- 路由注册防腐与别名兼容规则：[[A01-fr路由注册与防腐蚀]]
- demo slug 规范与历史别名机制：[[A06-Demo-Slug别名]]
- 相关文件：`lib/core/schema/fr_*.dart` + `lib/core/schema/handlers/*.dart`；测试 `test/core/schema/{fr_uri,fr_router,fr_route_handler,migration}_test.dart`（41 case）
