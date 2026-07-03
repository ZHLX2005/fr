# Flutter 自定义 Scheme 路由中心化（fr:// Router）

## 项目背景

小豆子 FR 项目里 `fr://` 内部 URL 处理分散在 5 个模块（文本链接、MethodChannel 反注册、桌面 widget、demo 反注册、内部代码），每加一个核心页要改 3 处，逻辑重复且不统一。本次重构收敛到 `lib/core/schema/` 一个注册中心。

## 关键难点和技术点

### 问题根因：5 处入口不一致

| 位置 | 行为 | 痛点 |
|------|------|------|
| `schema_service.dart` | `_registerCorePages()` 硬编码 4 个 core page | 与 `schema_navigator.dart` switch case 重复 |
| `schema_navigator.dart` | 4 个 if/else + 4 个 switch case；`setNavigatorKey` 静态全局 | 加新核心页要改 2 处 |
| `main.dart` | 4 个 `_navigateToXxx` 平行存在；硬编码 demo key `'Notion 图床'` / `'日历待办'` | 与 schema 层平行存在 |
| `lab/demos/*_demo.dart` | 36 个 demo 用 `demoRegistry.register(WidgetClass())` | demo key 与 fr:// 路由映射在 `SchemaRegistry.discover()` 里二次生成 |
| `message_strategy/text_link_message_strategy.dart` | 复用 `SchemaText`，依赖 SchemaNavigator | 链路长、错位难追 |

**核心矛盾**：同一个"路由"概念，被 5 处不同代码独立实现，新增/修改都要改多处。

### 解决方案：单注册中心 + 强类型 Handler

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

这是本次重构**最深的坑**，差点让整套嵌套路由失效。

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

| 输入 | 无边界检查 | 有边界检查 |
|------|-----------|-----------|
| `fr://lab` | ✅ 命中 `lab` | ✅ 命中 `lab` |
| `fr://lab/demo/clock` | ✅ 命中 `lab/demo` | ✅ 命中 `lab/demo` |
| `fr://labfoo` | ❌ 误命中 `lab`（startsWith('lab') 为 true） | ✅ 返回 null（`lab/` 不匹配） |

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

main.dart 原本有 4 个 `_navigateToXxx` 方法处理桌面 widget 的 MethodChannel 反注册。重构后合并为一个 switch：

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

## 防重复 Push 保护（容易在重构时丢失）

原 `_pushOnceIfNotOnTop` 用栈顶 `RouteSettings.name` 做去重，防止"返回手势多重折叠"bug（桌面 widget 多次唤起同一页面会堆叠）。重构 FrNavigator 时这个保护**差点被静默移除**——只 `nav.push(...)` 不检查栈顶。

### OK Example（popUntil 只读探查栈顶）

```dart
final routeName = '/fr/${match.authority}/${match.path}';
String? currentName;
// popUntil 谓词返回 true 立即停止，不会 pop 任何页面 — 只读探查
nav.popUntil((route) {
  currentName = route.settings.name;
  return true;
});
if (currentName == routeName) return;  // 栈顶已是该页面，跳过
nav.push(MaterialPageRoute(
  settings: RouteSettings(name: routeName),
  builder: (_) => target,
));
```

**教训**：重构 Navigator 相关代码时，**防重复 push 保护是隐性合约**——单元测试很难覆盖（需要 widget 测试模拟多次 MethodCall）。code review 时要专门检查 push 路径有没有保留去重逻辑。

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
    │  3. popUntil 探查栈顶 │  ← 防重复 push
    │  4. nav.push         │
    └─────────────────────┘
                │
       错误: SnackBar + debugPrint
```

---

## 错误处理矩阵

| 错误 | 表现 |
|------|------|
| scheme 非 `fr://` | `debugPrint` + 静默返回 |
| 找不到 authority | `debugPrint` + SnackBar "未知路由" |
| handler 返回 null Widget | 静默 debugPrint（防御） |
| handler 抛异常 | SnackBar 显示 e.message + debugPrint stacktrace |
| context.mounted=false | 跳过 push，记录日志 |
| NavigatorState 为 null | debugPrint + 静默返回 |

---

## 迁移策略（一次性彻底）

| 当前 | 新 |
|------|-----|
| `SchemaNavigator.navigateToCorePage` switch | `LabCoreHandler` 处理 lab/core/* |
| `SchemaNavigator.navigateToDemo` demoRegistry 查询 | `LabDemoHandler` 处理 lab/demo/* |
| `SchemaNavigator.navigateToLab` | `LabIndexHandler` 处理 fr://lab |
| `main.dart._navigateToLab/Calendar/Timetable/NotionImage` | 4 个 MethodChannel handler → `FrNavigator.handle(fr://...)` |
| `notion_image_host_demo.dart` | 保留 demo 注册，同时注册 `fr://notion/image-host` |

**删除清单**（老 API 全部下线）：
- `schema_service.dart`（SchemaRoutes / SchemaRegistry / schemaRegistry）
- `schema_navigator.dart`（SchemaNavigator）
- `schema_parser.dart`（autoLink 逻辑搬到 schema_text.dart 私有方法）

**保留**：`lib/lab/lab_container.dart` 的 `DemoRegistry` / `demoRegistry` —— 是 lab 模块基础设施，被 36 个 demo 文件直接调用，与 fr:// 路由无强耦合。`LabDemoHandler` 仅作为消费者通过 `demoRegistry.get(key)` 查询。

---

## 经验总结

| 教训 | 应用场景 |
|------|---------|
| 自定义 scheme 路由的 host 段不能只取第一个 `/` 前，否则嵌套路由失效 | 任何需要嵌套命名空间的路由系统 |
| Router prefix 匹配必须有 slash 边界保护，防 `labfoo` 误命中 `lab` | 任何用 startsWith 做路由匹配的场景 |
| 路由测试必须断言具体 handler 类型，不能只断言非 null | 路由 / 分发 / 策略模式系统的测试 |
| query string 工具方法（queryBool/queryString/pathSegment）放 FrRouteMatch 上 | 需要传参的 deep link 场景 |
| MethodChannel 反注册可翻译成内部 URL，统一分发链路 | Flutter 与 native 桥接的路由统一 |
| 防重复 push 是隐性合约，重构 Navigator 时要专门检查 | 任何涉及多次 push 的入口（widget 回调、onNewIntent） |

---

## 相关文件

- Spec: `docs/superpowers/specs/2026-07-03-fr-url-router-design.md`
- Plan: `docs/superpowers/plans/2026-07-03-fr-url-router.md`
- 核心实现：`lib/core/schema/fr_*.dart` + `lib/core/schema/handlers/*.dart`
- 测试：`test/core/schema/{fr_uri,fr_router,fr_route_handler,migration}_test.dart`（41 个 case）
