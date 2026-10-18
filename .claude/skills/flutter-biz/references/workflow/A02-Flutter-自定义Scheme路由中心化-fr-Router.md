# Flutter 自定义 Scheme 路由中心化（fr:// Router）

## 解决方案：单注册中心 + 强类型 Handler

```
lib/core/schema/
├── fr_uri.dart              # URI 解析（authority/path/query 拆分）
├── fr_route.dart            # 路由条目（authority + handler 引用）
├── fr_route_handler.dart    # 抽象基类 + FrRouteMatch（工具方法）
├── fr_router.dart           # 单例注册中心（register/registerAll/findHandler/resolve）
├── fr_navigator.dart        # 替换原 SchemaNavigator（push 封装）
├── bootstrap_routes.dart    # 集中注册（main 启动时调）
└── handlers/
    ├── lab_index_handler.dart        # fr://lab
    ├── lab_demo_handler.dart         # fr://lab/demo/{key}
    ├── lab_core_handler.dart         # fr://lab/core/{key}
    ├── notion_image_host_handler.dart # fr://notion/image-host?autocapture=
    ├── notion_create_page_handler.dart # fr://notion/create-page?databaseId=
    └── timetable_handler.dart        # fr://timetable
```

3 个入口（文本 / MethodChannel / 内部代码）全部调 `FrNavigator.handle(context, url)`，由 router 统一解析 + 找 handler + push。

---

## ⚠️ Critical 设计陷阱：FrUri 拆 host 还是 authority

这是嵌套路由**最深的坑**，差点让整套嵌套路由失效。

### NOK Example（错误拆法 — host 取第一个 `/` 前）

```dart
// ❌ 错误：把第一个 '/' 前作为 host
final slashIdx = pathAndHost.indexOf('/');
final host = slashIdx == -1 ? pathAndHost : pathAndHost.substring(0, slashIdx);
final path = slashIdx == -1 ? '' : pathAndHost.substring(slashIdx + 1);

// 后果：
// fr://lab/demo/clock → host='lab', path='demo/clock'
// fr://lab/core/profile → host='lab', path='core/profile'
// 路由只能命中 register('lab', ...) 一个 key
// → fr://lab/demo/clock 和 fr://lab/core/profile 全部路由到 LabIndexHandler ❌
```

**问题**：host 是单段字符串，无法表达 `lab/demo` / `lab/core` 这种嵌套命名空间。

### OK Example（正确拆法 — authority 整段作 key + path 拆段）

```dart
class FrUri {
  final String scheme;
  final String authority;  // '?' 前整段，可含 '/'
  final String path;       // authority 内第一个 '/' 后的部分
  final Map<String, String> query;

  static FrUri? tryParse(String raw) {
    // ...
    final querySplitIdx = afterScheme.indexOf('?');
    final authorityPart = querySplitIdx == -1
        ? afterScheme
        : afterScheme.substring(0, querySplitIdx);
    if (authorityPart.isEmpty) return null;

    // authority 整段保留；path 是 authority 内第一个 '/' 后的部分
    final slashIdx = authorityPart.indexOf('/');
    final authority = authorityPart;  // 整段
    final path = slashIdx == -1
        ? ''
        : Uri.decodeComponent(authorityPart.substring(slashIdx + 1));
    // ...
  }
}
```

**结果**：

- `fr://lab` → authority=`lab`, path=``
- `fr://lab/demo/clock` → authority=`lab/demo/clock`, path=`demo/clock`
- `fr://notion/image-host?autocapture=true` → authority=`notion/image-host`, path=`image-host`

---

## ⚠️ 中文 URL 陷阱：Uri.decodeComponent 对原始中文抛异常

生产 bug 教训：藏在 41 个绿测试里，导致所有含中文的 fr:// URL 跳转崩溃（用户报告"lab/demos 无法跳转"）。

### 根因

`Uri.decodeComponent` 期望输入是 **percent-encoded** 形式（如 `%E6%97%B6%E9%92%9F`）。当输入是**原始中文字符串**（如 `时钟`），内部按字节扫描 `%` 序列时，遇到中文 UTF-8 字节的特定组合会判定为非法 percent encoding，抛 `ArgumentError: Illegal percent encoding in URI`。

```dart
Uri.decodeComponent('lab/demo/时钟');                       // ❌ 抛 ArgumentError
Uri.decodeComponent('lab/demo/%E6%97%B6%E9%92%9F');         // ✅ 返回 'lab/demo/时钟'
```

### 症状

含中文的 URL 全崩，纯英文的好 —— 这是定位根因的关键信号：

| URL                        | 含中文? | 行为                                                  |
| -------------------------- | ------- | ----------------------------------------------------- |
| `fr://notion/image-host` | 否      | ✅ 正常跳转                                           |
| `fr://timetable`         | 否      | ✅ 正常跳转                                           |
| `fr://lab/demo/时钟`     | 是      | ❌ resolve 崩溃 → FrNavigator 静默失败 → 点击无反应 |
| `fr://lab/demo/日历待办` | 是      | ❌ 桌面 widget 进 app 不跳转                          |

### 为什么 41 个测试没抓住

测试用编码形式，生产用原始中文 —— 两条路径不重合：

```dart
// 测试（能过 — 走 decode 正常路径）
FrUri.tryParse('fr://lab/demo/%E6%97%85%E8%A1%8C');

// 生产（崩溃 — 走原始中文路径，没覆盖）
'navigateToCalendar' => 'fr://lab/demo/日历待办';
```

**教训**：URL 解析测试必须覆盖**原始中文输入**，不能只用 `%` 编码形式。

### 修复（双保险）

**1. safeDecode**（防御 — 即使 URL 含中文也不崩）：

```dart
static String _safeDecode(String s) {
  if (!s.contains('%')) return s;       // 无 % 直接返回，避开中文陷阱
  try {
    return Uri.decodeComponent(s);
  } catch (_) {
    return s;                            // 非法 % 序列也容错
  }
}
```

**2. ASCII slug 规范**（根治 — URL 不含中文）：

demo 用英文 slug 作 URL key（`fr://lab/demo/clock`），中文 title（`时钟`）仅作显示文字。
slug 通过 `DemoPage.slug` abstract getter 强制每个 demo 子类自带（全局 `kDemoSlugs` map 不存在；旧 slug 通过别名机制兼容）。
历史 slug 通过 `demoRegistry.register(demo, key: alias)` 别名机制兼容。详见 [[A06-Flutter-Demo-slug别名与Tab合并SOP]] 与规范 ref「命名约定」。

### 测试教训

```dart
// ✅ 必须覆盖原始中文（回归保护）
test('原始中文 URL 不崩', () {
  expect(FrUri.tryParse('fr://lab/demo/时钟'), isNotNull);
  expect(FrUri.tryParse('fr://lab/demo/时钟')!.authority, 'lab/demo/时钟');
});
```

---

## Router Prefix 匹配 + Slash 边界保护

因为路由键可能是嵌套的（`lab`、`lab/demo`、`notion/image-host`），router 不能用简单的 `Map[key]` 查找。

### 核心算法（最长前缀 + slash 边界）

```dart
FrRouteHandler? findHandler(String authority) {
  // 按 key 长度降序，保证最长前缀优先（lab/demo 优先于 lab）
  final sortedKeys = _routes.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));

  for (final key in sortedKeys) {
    if (authority == key) return _routes[key]!.handler;
    // 前缀匹配必须以 '/' 分隔，防止 'labfoo' 误命中 'lab'
    if (authority.startsWith('$key/')) return _routes[key]!.handler;
  }
  return null;
}
```

### 为什么必须 slash 边界检查

| 输入                    | 无边界检查                                    | 有边界检查                      |
| ----------------------- | --------------------------------------------- | ------------------------------- |
| `fr://lab`            | ✅ 命中`lab`                                | ✅ 命中`lab`                  |
| `fr://lab/demo/clock` | ✅ 命中`lab/demo`                           | ✅ 命中`lab/demo`             |
| `fr://labfoo`         | ❌ 误命中`lab`（startsWith('lab') 为 true） | ✅ 返回 null（`lab/` 不匹配） |

**测试必须覆盖这个边界 case**：

```dart
test('fr://labfoo 不会误命中 lab（无 slash 边界）', () async {
  final match = await frRouter.resolve('fr://labfoo');
  expect(match, isNull);  // 不是 LabIndexHandler
});
```

---

## ⚠️ 测试断言教训：不要只断言非 null

本次 critical bug 之所以能藏在 Task 1-9 都"测试通过"的状态下，是因为测试只写了：

```dart
// ❌ 危险：只断言非 null，bug 藏在里面
test('fr://lab/demo/clock resolves', () async {
  final match = await frRouter.resolve('fr://lab/demo/clock');
  expect(match, isNotNull);  // 通过！但其实命中的是错的 handler
});
```

### OK Example（断言具体 handler 类型）

```dart
// ✅ 正确：断言具体 handler 类型 + 反向断言不是兄弟 handler
test('fr://lab/demo/clock resolves to LabDemoHandler', () async {
  final match = await frRouter.resolve('fr://lab/demo/clock');
  expect(match, isNotNull);
  expect(frRouter.findHandler(match!.authority), isA<LabDemoHandler>());
  // 关键回归保护：不能退化成命中父级 handler
  expect(frRouter.findHandler(match.authority), isNot(isA<LabIndexHandler>()));
});
```

**教训**：路由系统的测试**必须**断言"命中了哪个具体 handler"，不能只验证"解析成功"。否则嵌套层级错位时测试全绿但功能全错。

---

## Handler 模式：强类型 + query string 工具方法

### 抽象基类

```dart
abstract class FrRouteHandler {
  const FrRouteHandler();
  Widget build(BuildContext context, FrRouteMatch match);
}

class FrRouteMatch {
  final FrUri uri;
  String get authority => uri.authority;
  String get path => uri.path;
  Map<String, String> get query => uri.query;

  String? queryString(String key) => query[key];

  // queryBool 接受 'true'/'1'，其他为 defaultValue
  bool queryBool(String key, {bool defaultValue = false}) {
    final v = query[key];
    if (v == null) return defaultValue;
    return v == 'true' || v == '1';
  }

  // pathSegment 拆 path 按 '/'，越界抛 RangeError
  String pathSegment(int index) {
    if (path.isEmpty) throw RangeError.index(index, path, 'path is empty');
    final segments = path.split('/');
    if (index < 0 || index >= segments.length) {
      throw RangeError.index(index, segments, 'path segments');
    }
    return segments[index];
  }
}
```

### Handler 实现示例（带 query string）

```dart
/// fr://notion/image-host?autocapture={true|false}
class NotionImageHostHandler extends FrRouteHandler {
  const NotionImageHostHandler();

  @override
  Widget build(BuildContext context, FrRouteMatch match) {
    // 直接用工具方法取 query bool
    final autocapture = match.queryBool('autocapture');
    return NotionImageHostDeepLinkPage(autocapture: autocapture);
  }
}
```

### 集中注册

```dart
void registerAllFrRoutes() {
  frRouter.registerAll([
    FrRoute('lab',               handler: const LabIndexHandler()),
    FrRoute('lab/demo',          handler: const LabDemoHandler()),
    FrRoute('lab/core',          handler: const LabCoreHandler()),
    FrRoute('notion/image-host', handler: const NotionImageHostHandler()),
    FrRoute('notion/create-page',handler: const NotionCreatePageHandler()),
    FrRoute('timetable',         handler: const TimetableHandler()),
  ]);
}
```

---

## MethodChannel 反注册 → fr:// URL 翻译

main.dart 用一个 switch 分发桌面 widget 的 MethodChannel 反注册（统一翻译成 `fr://...` URL 后走 `FrNavigator.handle`）：

```dart
Future<dynamic> _handleMethodCall(MethodCall call) async {
  // 4 个 method 全部翻译成 fr:// URL，统一走 FrNavigator
  final frUrl = switch (call.method) {
    'navigateToLab'        => 'fr://lab',
    'navigateToCalendar'   => 'fr://lab/demo/日历待办',
    'navigateToTimetable'  => 'fr://timetable',
    'navigateToNotionImage'=> 'fr://notion/image-host?autocapture=${(call.arguments as bool?) ?? false}',
    _ => null,
  };
  if (frUrl == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    FrNavigator.handle(navigatorKey.currentContext, frUrl);
  });
}
```

**收益**：

- 新增 MethodChannel 入口只需加一行 switch case
- query 参数（autocapture）序列化到 URL，handler 端用 `queryBool` 解析
- 与文本链接、内部代码走完全相同的分发链路

---

## 防重复 Push 保护（CLEAR_TOP 语义，容易在重构时退化）

桌面 widget / onNewIntent / 文本链接任一入口反复触发，目标页面会被多次 push，导致"返回手势要折叠多次才能退出"。`FrNavigator.handle` 用 **CLEAR_TOP 语义**根治：目标路由已在栈中（任意深度）→ `popUntil` 把它提到栈顶，不再 push；不在栈中 → 正常 push。

### 关键点：Navigator 无法只读扫描全栈

`Navigator` 公共 API 没有"列出当前栈"的方法，`popUntil` 会边查边 pop（破坏性）。要做非破坏性的"目标是否已在栈中"判断，必须挂一个 `NavigatorObserver` 同步跟踪栈：

```dart
class FrRouteStack extends NavigatorObserver {
  final List<Route<dynamic>> _routes = [];

  bool containsName(String name) =>
      _routes.any((r) => r.settings.name == name);

  @override
  void didPush(Route r, Route<dynamic>? prev) => _routes.add(r);
  @override
  void didPop(Route r, Route<dynamic>? prev) => _routes.remove(r);
  @override
  void didRemove(Route r, Route<dynamic>? prev) => _routes.remove(r);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (i >= 0 && newRoute != null) _routes[i] = newRoute;
    else if (newRoute != null) _routes.add(newRoute);
  }
}

final frRouteStack = FrRouteStack();
// main.dart: MaterialApp(navigatorObservers: [frRouteStack], ...)
```

### OK Example（popUntil 提到已存在实例）

```dart
final routeName = '/fr/${match.authority}/${match.path}';
if (frRouteStack.containsName(routeName)) {
  // 已在栈中 → 把它上面的页面全部 pop，提到栈顶；route.isFirst 是保险
  nav.popUntil((route) =>
      route.settings.name == routeName || route.isFirst);
  return;  // 不再 push
}
nav.push(MaterialPageRoute(
  settings: RouteSettings(name: routeName),
  builder: (_) => target,
));
```

### ⚠️ 旧实现（仅查栈顶）为什么不够

历史实现只用 `popUntil` 谓词立即返回 true 来只读探查**栈顶**一个 route：

```dart
// ❌ 旧：只查栈顶，交替点击 / 目标页之上压了其他页面时失效
String? currentName;
nav.popUntil((route) {
  currentName = route.settings.name;
  return true;  // 立即停止，只读到栈顶
});
if (currentName == routeName) return;
nav.push(...);
```

**失效场景**：点时钟 widget → `[Main, Clock]`；点日历 widget → `[Main, Clock, Calendar]`；再点时钟 → 旧逻辑看栈顶是 Calendar ≠ Clock → 又 push → `[Main, Clock, Calendar, Clock]`……栈无限累加，返回键在重复页之间循环，根页面无法直接退出。CLEAR_TOP 把"是否已在栈中"扩到任意深度，根治累加。

**教训**：
1. **防重复 push 保护是隐性合约**——单元测试很难覆盖（需 widget 测试模拟多次 MethodCall），code review 要专门检查 push 路径的去重逻辑。
2. 去重判断范围要覆盖**全栈**而非仅栈顶，否则"交替点击 / 嵌套导航"会绕过去重。

---

## 完整数据流

```
3 个入口
┌─ 文本: SchemaText.onLinkTap ──────────────┐
├─ MethodChannel: main.dart _handleMethodCall ┤
└─ 内部代码: FrNavigator.handle(ctx, url) ────┘
                │
                ▼
    ┌─────────────────────┐
    │ FrNavigator.handle  │
    │  1. frRouter.resolve │  ← 解析 URL + 找 handler
    │  2. handler.build    │  ← 拿 query/path 构造 Widget
    │  3. CLEAR_TOP 防重  │  ← 已在栈中→popUntil 提到栈顶；否则 push
    │  4. nav.push         │
    └─────────────────────┘
                │
       错误: SnackBar + debugPrint
```

---

## 错误处理矩阵

| 错误                     | 表现                                            |
| ------------------------ | ----------------------------------------------- |
| scheme 非`fr://`       | `debugPrint` + 静默返回                       |
| 找不到 authority         | `debugPrint` + SnackBar "未知路由"            |
| handler 返回 null Widget | 静默 debugPrint（防御）                         |
| handler 抛异常           | SnackBar 显示 e.message + debugPrint stacktrace |
| context.mounted=false    | 跳过 push，记录日志                             |
| NavigatorState 为 null   | debugPrint + 静默返回                           |

---

## 经验总结

| 教训                                                                         | 应用场景                                             |
| ---------------------------------------------------------------------------- | ---------------------------------------------------- |
| 自定义 scheme 路由的 host 段不能只取第一个`/` 前，否则嵌套路由失效         | 任何需要嵌套命名空间的路由系统                       |
| Router prefix 匹配必须有 slash 边界保护，防`labfoo` 误命中 `lab`         | 任何用 startsWith 做路由匹配的场景                   |
| 路由测试必须断言具体 handler 类型，不能只断言非 null                         | 路由 / 分发 / 策略模式系统的测试                     |
| query string 工具方法（queryBool/queryString/pathSegment）放 FrRouteMatch 上 | 需要传参的 deep link 场景                            |
| MethodChannel 反注册可翻译成内部 URL，统一分发链路                           | Flutter 与 native 桥接的路由统一                     |
| 防重复 push 是隐性合约，Navigator 改动时要专门检查                          | 任何涉及多次 push 的入口（widget 回调、onNewIntent） |

---

## 相关文件

- 核心实现：`lib/core/schema/fr_*.dart` + `lib/core/schema/handlers/*.dart`
- 测试：`test/core/schema/{fr_uri,fr_router,fr_route_handler,migration}_test.dart`（41 个 case）
