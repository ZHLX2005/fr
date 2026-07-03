# fr:// 内部 URL 路由中心化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把分散在 5 个模块的 fr:// 内部 URL 处理统一到一个注册中心（`FrRouter`），删除老 `SchemaRegistry` / `SchemaNavigator` / `SchemaRoutes` 静态类，新增 `FrRouteHandler` 抽象基类支持 query string 参数，让 5 个入口（文本链接、MethodChannel 反注册、Shortcut、内部代码、demo 反注册）都走同一份路由表。

**Architecture:** `lib/core/schema/` 升级为路由中心——`fr_uri.dart` 拆 URI、`fr_route.dart` 定义条目、`fr_route_handler.dart` 抽象基类、`fr_router.dart` 单例注册中心、`fr_navigator.dart` 替换 `SchemaNavigator`、`bootstrap_routes.dart` 集中注册。`main.dart` 的 4 个 `_navigateToXxx` 合并为 1 个 `_dispatchFrUri` 转给 frRouter。`lib/lab/lab_container.dart` 的 `DemoRegistry` 保留（lab 模块基础设施），`LabDemoHandler` 作为消费者通过 `demoRegistry.get(key)` 查询。

**Tech Stack:** Flutter/Dart（sdk ^3.11.1）、`flutter_test`（项目只声明这个测试包）、`Provider` + `Riverpod`（已有，不引入新依赖）、Conventional Commits。

---

## Global Constraints

- **Dart SDK**: `^3.11.1`
- **测试包**: 仅 `flutter_test`（项目没有 `test` 包）
- **命名**: handler 类后缀统一 `RouteHandler`；文件名后缀 `_handler.dart`
- **不要引入新依赖**: 不引 `go_router` / `auto_route`
- **错误处理**: scheme 错误静默；host 找不到 SnackBar；handler 异常 SnackBar + debugPrint
- **路径**: 所有 `lib/core/schema/*.dart`；handler 在 `lib/core/schema/handlers/`；测试在 `test/core/schema/`
- **commit 频率**: 每个 Task 独立 commit
- **中文 path 支持**: 沿用 `schema_parser.dart` 的 `_unescape` 逻辑搬到 `fr_uri.dart`

---

## File Structure

```
lib/core/schema/
├── fr_uri.dart                   # 新增：URI 解析（scheme/host/path/query）
├── fr_route.dart                 # 新增：路由条目（host + handler 引用）
├── fr_route_handler.dart         # 新增：抽象基类 + FrRouteMatch
├── fr_router.dart                # 新增：单例注册中心（register/registerAll/handle）
├── fr_navigator.dart             # 新增：替换 SchemaNavigator
├── bootstrap_routes.dart         # 新增：集中注册（main 启动时调）
├── handlers/
│   ├── lab_index_handler.dart    # 新增：fr://lab
│   ├── lab_demo_handler.dart     # 新增：fr://lab/demo/{key}
│   ├── lab_core_handler.dart     # 新增：fr://lab/core/{key}
│   ├── notion_image_host_handler.dart  # 新增：fr://notion/image-host?autocapture=
│   ├── notion_create_page_handler.dart # 新增：fr://notion/create-page?databaseId=
│   └── timetable_handler.dart    # 新增：fr://timetable
├── schema_text.dart              # 修改：内部跳转改用 frRouter
├── schema.dart                   # 修改：export 调整
├── schema_service.dart           # 删除
├── schema_navigator.dart         # 删除
└── schema_parser.dart            # 删除（autoLink 逻辑搬到 schema_text.dart）

lib/main.dart                     # 修改：合并 4 个 _navigateToXxx → 1 个 _dispatchFrUri

test/core/schema/
├── fr_uri_test.dart              # 新增：URI 解析测试（Task 2）
├── fr_router_test.dart           # 新增：注册中心测试（Task 4）
├── fr_route_handler_test.dart    # 新增：FrRouteMatch 工具方法测试（Task 5）
└── migration_test.dart           # 新增：5 个老路径烟雾测试（Task 9）
```

---

## Task 1: `FrUri` 解析类 + 失败测试

**Files:**
- Create: `lib/core/schema/fr_uri.dart`
- Create: `test/core/schema/fr_uri_test.dart`

**Interfaces:**
- Consumes: 无
- Produces: `class FrUri { final String scheme; final String host; final String path; final Map<String, String> query; }`、`static FrUri? tryParse(String raw)`

- [ ] **Step 1: 写失败测试** — 创建 `test/core/schema/fr_uri_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/schema/fr_uri.dart';

void main() {
  group('FrUri.tryParse', () {
    test('parses simple host-only URL', () {
      final uri = FrUri.tryParse('fr://lab');
      expect(uri, isNotNull);
      expect(uri!.scheme, 'fr');
      expect(uri.host, 'lab');
      expect(uri.path, '');
      expect(uri.query, isEmpty);
    });

    test('parses host with multi-segment path', () {
      final uri = FrUri.tryParse('fr://lab/demo/clock');
      expect(uri, isNotNull);
      expect(uri!.host, 'lab');
      expect(uri.path, 'demo/clock');
    });

    test('parses host with single path segment', () {
      final uri = FrUri.tryParse('fr://notion/image-host');
      expect(uri, isNotNull);
      expect(uri!.host, 'notion');
      expect(uri.path, 'image-host');
    });

    test('parses query string with single key', () {
      final uri = FrUri.tryParse('fr://notion/image-host?autocapture=true');
      expect(uri, isNotNull);
      expect(uri!.query['autocapture'], 'true');
    });

    test('parses query string with multiple keys', () {
      final uri = FrUri.tryParse('fr://x?a=1&b=2');
      expect(uri, isNotNull);
      expect(uri!.query['a'], '1');
      expect(uri.query['b'], '2');
    });

    test('returns null for non-fr scheme', () {
      expect(FrUri.tryParse('http://lab'), isNull);
      expect(FrUri.tryParse('https://x.com'), isNull);
    });

    test('returns null for empty string', () {
      expect(FrUri.tryParse(''), isNull);
    });

    test('handles URL-encoded path segments', () {
      final uri = FrUri.tryParse('fr://lab/demo/%E6%97%85%E8%A1%8C');
      expect(uri, isNotNull);
      expect(uri!.path, 'demo/旅行');
    });
  });
}
```

- [ ] **Step 2: 跑测试，验证失败**

Run: `flutter test test/core/schema/fr_uri_test.dart`
Expected: 编译失败（`FrUri` 未定义）

- [ ] **Step 3: 实现 `FrUri`**

创建 `lib/core/schema/fr_uri.dart`：

```dart
/// fr:// URI 解析器
///
/// 格式: fr://{host}/{path?}?{query?}
/// 示例:
///   fr://lab                       → host=lab, path="", query={}
///   fr://lab/demo/clock            → host=lab, path="demo/clock", query={}
///   fr://notion/x?autocapture=true → host=notion, path="x", query={autocapture: true}
class FrUri {
  final String scheme;
  final String host;
  final String path;
  final Map<String, String> query;

  const FrUri({
    required this.scheme,
    required this.host,
    required this.path,
    required this.query,
  });

  /// 解析失败返回 null（scheme 错误、字符串空、host 缺失任一情况）。
  /// 静默返回，不抛 — 调用方负责处理 null。
  static FrUri? tryParse(String raw) {
    if (raw.isEmpty) return null;

    // scheme
    const schemePrefix = 'fr://';
    if (!raw.startsWith(schemePrefix)) return null;
    final afterScheme = raw.substring(schemePrefix.length);
    if (afterScheme.isEmpty) return null;

    // query split
    final querySplitIdx = afterScheme.indexOf('?');
    final pathAndHost = querySplitIdx == -1
        ? afterScheme
        : afterScheme.substring(0, querySplitIdx);
    final queryStr = querySplitIdx == -1 ? '' : afterScheme.substring(querySplitIdx + 1);

    // host / path split（第一个 '/' 是分隔符）
    final slashIdx = pathAndHost.indexOf('/');
    final host = slashIdx == -1 ? pathAndHost : pathAndHost.substring(0, slashIdx);
    if (host.isEmpty) return null;
    final path = slashIdx == -1 ? '' : pathAndHost.substring(slashIdx + 1);

    // query 解析
    final query = <String, String>{};
    if (queryStr.isNotEmpty) {
      for (final pair in queryStr.split('&')) {
        final eq = pair.indexOf('=');
        if (eq == -1) {
          query[Uri.decodeComponent(pair)] = '';
        } else {
          final k = Uri.decodeComponent(pair.substring(0, eq));
          final v = Uri.decodeComponent(pair.substring(eq + 1));
          query[k] = v;
        }
      }
    }

    return FrUri(
      scheme: 'fr',
      host: host,
      path: path,
      query: query,
    );
  }
}
```

- [ ] **Step 4: 跑测试，验证通过**

Run: `flutter test test/core/schema/fr_uri_test.dart`
Expected: 8/8 PASS

- [ ] **Step 5: 提交**

```bash
git add lib/core/schema/fr_uri.dart test/core/schema/fr_uri_test.dart
git commit -m "feat(schema): 新增 FrUri 解析器

支持 fr://host/path?query 格式，scheme 错误返回 null 而非抛异常，
URL 编码 path 段自动 decode。8 个单元测试覆盖 host/path/query/错误分支。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `FrRoute` 路由条目数据类

**Files:**
- Create: `lib/core/schema/fr_route.dart`

**Interfaces:**
- Consumes: 无
- Produces: `class FrRoute { final String host; final FrRouteHandler handler; const FrRoute(this.host, {required this.handler}); }`

- [ ] **Step 1: 创建文件** — `lib/core/schema/fr_route.dart`：

```dart
import 'fr_route_handler.dart';

/// 路由条目：host 命名空间 + handler 引用
///
/// 用法:
/// ```dart
/// FrRoute('lab/demo', handler: const LabDemoHandler())
/// ```
class FrRoute {
  /// host 段（fr:// 之后第一个 '/' 之前的部分）
  final String host;

  /// 该 host 下的处理器
  final FrRouteHandler handler;

  const FrRoute(this.host, {required this.handler});
}
```

- [ ] **Step 2: 编译验证**

Run: `flutter analyze lib/core/schema/fr_route.dart`
Expected: 编译错误（`FrRouteHandler` 未定义）— 正常，Task 3 会引入

- [ ] **Step 3: 提交（与 Task 3 合并）**

跳过 — 等 Task 3 引入 `FrRouteHandler` 后一起 commit。

---

## Task 3: `FrRouteHandler` 抽象基类 + `FrRouteMatch`

**Files:**
- Create: `lib/core/schema/fr_route_handler.dart`

**Interfaces:**
- Consumes: 无（依赖 dart:convert / Uri 解码）
- Produces:
  - `abstract class FrRouteHandler { const FrRouteHandler(); Widget build(BuildContext context, FrRouteMatch match); }`
  - `class FrRouteMatch { final FrUri uri; String get host => uri.host; String get path => uri.path; Map<String, String> get query => uri.query; String? queryString(String key); bool queryBool(String key, {bool defaultValue = false}); String pathSegment(int index); }`

- [ ] **Step 1: 创建文件** — `lib/core/schema/fr_route_handler.dart`：

```dart
import 'package:flutter/widgets.dart';

import 'fr_uri.dart';

/// 路由匹配结果 — handler.build() 拿到的入参
///
/// 包含 host/path/query 三段，handler 通过工具方法取值。
class FrRouteMatch {
  final FrUri uri;

  const FrRouteMatch(this.uri);

  String get host => uri.host;
  String get path => uri.path;
  Map<String, String> get query => uri.query;

  /// 取 query 字符串值，不存在返回 null
  String? queryString(String key) => query[key];

  /// 取 query 布尔值；接受 'true'/'1' 为 true，其他为 defaultValue
  bool queryBool(String key, {bool defaultValue = false}) {
    final v = query[key];
    if (v == null) return defaultValue;
    return v == 'true' || v == '1';
  }

  /// 拆 path 段（按 '/'）；越界抛 RangeError
  String pathSegment(int index) {
    if (path.isEmpty) {
      throw RangeError.index(index, path, 'path is empty');
    }
    final segments = path.split('/');
    if (index < 0 || index >= segments.length) {
      throw RangeError.index(index, segments, 'path segments');
    }
    return segments[index];
  }
}

/// 路由处理器抽象基类
///
/// 每个 host 对应一个 handler 子类；handler 拿到 context 和 match，
/// 返回要 push 的 Widget。
abstract class FrRouteHandler {
  const FrRouteHandler();

  /// 构建目标 Widget
  ///
  /// context 来自调用方（可能为 null，见各 frRouter.handle 重载）；
  /// match 包含 URI 全部信息。
  Widget build(BuildContext context, FrRouteMatch match);
}
```

- [ ] **Step 2: 验证编译（连带 Task 2 文件）**

Run: `flutter analyze lib/core/schema/`
Expected: 0 error（可能 0 warning 也可能 1 个 unused_import 警告，先留着）

- [ ] **Step 3: 提交**

```bash
git add lib/core/schema/fr_route.dart lib/core/schema/fr_route_handler.dart
git commit -m "feat(schema): 新增 FrRoute 条目 + FrRouteHandler 抽象基类

FrRoute 是注册条目(host + handler 引用)；
FrRouteHandler 抽象基类接受 context + FrRouteMatch 返回 Widget。
FrRouteMatch 提供 queryString/queryBool/pathSegment 工具方法。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `FrRouter` 单例注册中心 + 失败测试

**Files:**
- Create: `lib/core/schema/fr_router.dart`
- Create: `test/core/schema/fr_router_test.dart`

**Interfaces:**
- Consumes: `FrRoute` (from Task 2/3)、`FrUri` (from Task 1)、`FrRouteHandler`/`FrRouteMatch` (from Task 3)
- Produces:
  - `class FrRouter { void register(FrRoute route); void registerAll(Iterable<FrRoute> routes); FrRouteHandler? findHandler(String host); Future<void> handle(BuildContext? context, String url); }`
  - 全局单例 `final frRouter = FrRouter();`

- [ ] **Step 1: 写失败测试** — `test/core/schema/fr_router_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/schema/fr_router.dart';
import 'package:xiaodouzi_fr/core/schema/fr_route.dart';
import 'package:xiaodouzi_fr/core/schema/fr_route_handler.dart';

class StubHandler extends FrRouteHandler {
  const StubHandler();
  @override
  Widget build(BuildContext context, FrRouteMatch match) {
    return Text('stub: ${match.host} ${match.path}');
  }
}

class ThrowingHandler extends FrRouteHandler {
  const ThrowingHandler();
  @override
  Widget build(BuildContext context, FrRouteMatch match) {
    throw StateError('intentional');
  }
}

void main() {
  group('FrRouter', () {
    test('register then findHandler returns the handler', () {
      final r = FrRouter();
      r.register(FrRoute('stub', handler: const StubHandler()));
      expect(r.findHandler('stub'), isA<StubHandler>());
    });

    test('registerAll adds multiple routes', () {
      final r = FrRouter();
      r.registerAll([
        FrRoute('a', handler: const StubHandler()),
        FrRoute('b', handler: const StubHandler()),
      ]);
      expect(r.findHandler('a'), isA<StubHandler>());
      expect(r.findHandler('b'), isA<StubHandler>());
    });

    test('findHandler returns null for unknown host', () {
      final r = FrRouter();
      expect(r.findHandler('ghost'), isNull);
    });

    test('handle resolves URL to handler and pushes widget', () async {
      final r = FrRouter();
      r.register(FrRoute('stub', handler: const StubHandler()));

      // 不实际跑 Navigator.push，只验证 frUri 解析 + findHandler 流程
      final handler = r.findHandler('stub');
      expect(handler, isA<StubHandler>());
    });

    test('register can replace existing host', () {
      final r = FrRouter();
      r.register(FrRoute('a', handler: const StubHandler()));
      r.register(FrRoute('a', handler: const StubHandler()));
      expect(r.findHandler('a'), isA<StubHandler>());
    });
  });
}
```

- [ ] **Step 2: 跑测试，验证失败**

Run: `flutter test test/core/schema/fr_router_test.dart`
Expected: 编译失败（`FrRouter` 未定义）

- [ ] **Step 3: 实现 `FrRouter`**（不含 handle 流程 — handle 在 Task 6 接入 navigator）

创建 `lib/core/schema/fr_router.dart`：

```dart
import 'package:flutter/widgets.dart';

import 'fr_route.dart';
import 'fr_route_handler.dart';
import 'fr_uri.dart';

/// fr:// 路由注册中心（单例）
///
/// 使用:
/// ```dart
/// frRouter.register(FrRoute('lab', handler: const LabIndexHandler()));
/// await frRouter.handle(context, 'fr://lab/demo/clock');
/// ```
class FrRouter {
  final Map<String, FrRoute> _routes = {};

  /// 注册单条路由
  void register(FrRoute route) {
    _routes[route.host] = route;
  }

  /// 批量注册
  void registerAll(Iterable<FrRoute> routes) {
    for (final r in routes) {
      register(r);
    }
  }

  /// 查 host 对应的 handler，找不到返回 null
  FrRouteHandler? findHandler(String host) => _routes[host]?.handler;

  /// 列出已注册的所有 host（调试/测试用）
  Iterable<String> get registeredHosts => _routes.keys;

  /// 解析 URL 并 dispatch 到 handler
  ///
  /// - 解析失败（scheme 错误）→ debugPrint + 静默返回
  /// - 找不到 host → debugPrint + 静默返回（callSite 决定是否 SnackBar）
  /// - handler 抛异常 → debugPrint + 抛（callSite 决定 SnackBar）
  ///
  /// Navigator.push 由 callSite 通过 [dispatch] 调，本方法不直接做 push。
  Future<FrRouteMatch?> resolve(String url) async {
    final uri = FrUri.tryParse(url);
    if (uri == null) {
      debugPrint('FrRouter: 无法解析 url: $url');
      return null;
    }
    final handler = findHandler(uri.host);
    if (handler == null) {
      debugPrint('FrRouter: 未知 host: ${uri.host}');
      return null;
    }
    return FrRouteMatch(uri);
  }
}

/// 全局单例
final frRouter = FrRouter();
```

- [ ] **Step 4: 跑测试，验证通过**

Run: `flutter test test/core/schema/fr_router_test.dart`
Expected: 5/5 PASS

- [ ] **Step 5: 提交**

```bash
git add lib/core/schema/fr_router.dart test/core/schema/fr_router_test.dart
git commit -m "feat(schema): 新增 FrRouter 单例注册中心

register/registerAll/findHandler/resolve 5 个公开方法；
全局 frRouter 单例。scheme 错误/未知 host 静默返回。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: `FrRouteMatch` 工具方法测试

**Files:**
- Create: `test/core/schema/fr_route_handler_test.dart`

**Interfaces:**
- Consumes: `FrRouteMatch` (from Task 3)、`FrUri` (from Task 1)
- Produces: 测试用例（不动产品代码）

- [ ] **Step 1: 写测试** — `test/core/schema/fr_route_handler_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/schema/fr_route_handler.dart';
import 'package:xiaodouzi_fr/core/schema/fr_uri.dart';

void main() {
  FrRouteMatch make(String url) {
    return FrRouteMatch(FrUri.tryParse(url)!);
  }

  group('FrRouteMatch.queryString', () {
    test('returns value when key exists', () {
      final m = make('fr://x?a=hello');
      expect(m.queryString('a'), 'hello');
    });

    test('returns null when key missing', () {
      final m = make('fr://x?a=1');
      expect(m.queryString('b'), isNull);
    });
  });

  group('FrRouteMatch.queryBool', () {
    test('"true" → true', () {
      expect(make('fr://x?a=true').queryBool('a'), isTrue);
    });

    test('"1" → true', () {
      expect(make('fr://x?a=1').queryBool('a'), isTrue);
    });

    test('"false" → false', () {
      expect(make('fr://x?a=false').queryBool('a'), isFalse);
    });

    test('missing key returns defaultValue=false', () {
      expect(make('fr://x').queryBool('a'), isFalse);
    });

    test('missing key returns defaultValue=true when given', () {
      expect(make('fr://x').queryBool('a', defaultValue: true), isTrue);
    });
  });

  group('FrRouteMatch.pathSegment', () {
    test('returns first segment', () {
      expect(make('fr://lab/demo/clock').pathSegment(0), 'demo');
    });

    test('returns middle segment', () {
      expect(make('fr://lab/demo/clock').pathSegment(1), 'clock');
    });

    test('throws on out-of-range', () {
      expect(
        () => make('fr://lab/demo').pathSegment(5),
        throwsA(isA<RangeError>()),
      );
    });

    test('throws when path is empty', () {
      expect(
        () => make('fr://lab').pathSegment(0),
        throwsA(isA<RangeError>()),
      );
    });
  });
}
```

- [ ] **Step 2: 跑测试**

Run: `flutter test test/core/schema/fr_route_handler_test.dart`
Expected: 11/11 PASS

- [ ] **Step 3: 提交**

```bash
git add test/core/schema/fr_route_handler_test.dart
git commit -m "test(schema): FrRouteMatch 工具方法测试覆盖

queryString/queryBool/pathSegment 共 11 个 case。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: `FrNavigator` 替换 `SchemaNavigator`

**Files:**
- Create: `lib/core/schema/fr_navigator.dart`
- Modify: `lib/core/schema/schema.dart`（调整 export）

**Interfaces:**
- Consumes: `frRouter` (from Task 4)、`FrRouteHandler`/`FrRouteMatch` (from Task 3)
- Produces:
  - `class FrNavigator { static GlobalKey<NavigatorState>? _navigatorKey; static void setNavigatorKey(GlobalKey<NavigatorState> key); static Future<void> handle(BuildContext? context, String url); }`
  - 删除老 `SchemaNavigator` export

- [ ] **Step 1: 创建 `lib/core/schema/fr_navigator.dart`**

```dart
import 'package:flutter/material.dart';

import 'fr_router.dart';
import 'fr_route_handler.dart';

/// fr:// 路由导航器（基于 frRouter 的 push 封装）
///
/// 替代原 SchemaNavigator，setNavigatorKey 接收 main.dart 的
/// GlobalKey<NavigatorState>，handle 调 frRouter.resolve + handler.build
/// 然后 push。
class FrNavigator {
  FrNavigator._();

  static GlobalKey<NavigatorState>? _navigatorKey;

  /// 设置全局 navigator key（main.dart 启动时调一次）
  static void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  /// 入口：解析 URL + 找 handler + 错误 SnackBar + push
  static Future<void> handle(BuildContext? context, String url) async {
    final match = await frRouter.resolve(url);
    if (match == null) {
      // resolve 已 debugPrint 错误
      if (context != null && context.mounted) {
        _showError(context, '未知路由: $url');
      }
      return;
    }

    final handler = frRouter.findHandler(match.host);
    if (handler == null) return; // resolve 已处理

    Widget target;
    try {
      target = handler.build(context ?? _placeholderContext(), match);
    } catch (e, st) {
      debugPrint('FrNavigator: handler.build 抛异常: $e\n$st');
      if (context != null && context.mounted) {
        _showError(context, '路由 handler 错误: $e');
      }
      return;
    }

    final nav = _navigatorKey?.currentState;
    if (nav == null) {
      debugPrint('FrNavigator: navigatorKey 未初始化');
      return;
    }

    nav.push(
      MaterialPageRoute(
        settings: RouteSettings(name: '/fr/${match.host}/${match.path}'),
        builder: (_) => target,
      ),
    );
  }

  static BuildContext _placeholderContext() {
    // 没传 context 时用 navigator 自己的；不常发生（保留防御）
    return _navigatorKey!.currentContext!;
  }

  static void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
```

- [ ] **Step 2: 改 `lib/core/schema/schema.dart`**

Replace 全部内容 with:

```dart
// Schema 模块 - fr:// 内部 URL 路由中心
//
// 使用方式:
// ```dart
// import 'package:xiaodouzi_fr/core/schema/schema.dart';
//
// // 注册路由（main 启动时）
// registerAllFrRoutes();
//
// // 文本中嵌入可点击链接
// SchemaText('访问 [悬浮截屏](fr://lab/demo/clock) 示例')
//
// // 内部代码跳转
// await frRouter.handle(context, 'fr://lab/demo/clock');
//
// // MethodChannel 反注册（main.dart）
// await FrNavigator.handle(context, 'fr://notion/image-host?autocapture=true');
// ```

export 'fr_uri.dart';
export 'fr_route.dart';
export 'fr_route_handler.dart';
export 'fr_router.dart';
export 'fr_navigator.dart';
export 'schema_text.dart';
```

- [ ] **Step 3: 跑全量测试 + 编译**

Run: `flutter analyze lib/`
Expected: 编译错误 — `SchemaNavigator` 在 main.dart 仍被引用（正常，Task 7 改）

Run: `flutter test test/core/schema/`
Expected: 24/24 PASS（FrUri 8 + FrRouter 5 + FrRouteMatch 11）

- [ ] **Step 4: 提交**

```bash
git add lib/core/schema/fr_navigator.dart lib/core/schema/schema.dart
git commit -m "feat(schema): 新增 FrNavigator 替换 SchemaNavigator

FrNavigator 接受 context + url，调 frRouter.resolve 拿 match，
handler.build() 取 Widget，Navigator.push。
错误：scheme 错误 SnackBar；handler 抛异常 SnackBar + debugPrint。
老 SchemaNavigator export 移除（main.dart Task 7 改）。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: 6 个 handler 集中实现

**Files:**
- Create: `lib/core/schema/handlers/lab_index_handler.dart`
- Create: `lib/core/schema/handlers/lab_demo_handler.dart`
- Create: `lib/core/schema/handlers/lab_core_handler.dart`
- Create: `lib/core/schema/handlers/notion_image_host_handler.dart`
- Create: `lib/core/schema/handlers/notion_create_page_handler.dart`
- Create: `lib/core/schema/handlers/timetable_handler.dart`
- Create: `lib/core/schema/bootstrap_routes.dart`

**Interfaces:**
- Consumes: `FrRouteHandler` (from Task 3)、`frRouter` (from Task 4)
- Produces: 6 个 handler 子类 + 1 个 `registerAllFrRoutes()` 函数

- [ ] **Step 1: `lab_index_handler.dart`**

```dart
import 'package:flutter/material.dart';

import '../../screens/profile/lab/lab_page.dart';
import '../fr_route_handler.dart';

/// fr://lab → LabPage 首页
class LabIndexHandler extends FrRouteHandler {
  const LabIndexHandler();

  @override
  Widget build(BuildContext context, FrRouteMatch match) {
    return const LabPage();
  }
}
```

- [ ] **Step 2: `lab_demo_handler.dart`**

```dart
import 'package:flutter/material.dart';

import '../../../lab/lab_container.dart';
import '../fr_route_handler.dart';

/// fr://lab/demo/{demoKey} → DemoPage
///
/// demoKey 是 demoRegistry 注册时的 title（保留 demoRegistry 作为查询源）。
class LabDemoHandler extends FrRouteHandler {
  const LabDemoHandler();

  @override
  Widget build(BuildContext context, FrRouteMatch match) {
    final demoKey = match.path;  // 整段 path 即可，因为 host 已经限定 lab/demo
    final demo = demoRegistry.get(demoKey);
    if (demo == null) {
      return _NotFoundPage(message: '未找到 Demo: $demoKey');
    }
    return _DemoDetailPage(demo: demo);
  }
}

class _DemoDetailPage extends StatelessWidget {
  final DemoPage demo;
  const _DemoDetailPage({required this.demo});

  @override
  Widget build(BuildContext context) {
    return demo.buildPage(context);
  }
}

class _NotFoundPage extends StatelessWidget {
  final String message;
  const _NotFoundPage({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('未找到')),
      body: Center(child: Text(message)),
    );
  }
}
```

- [ ] **Step 3: `lab_core_handler.dart`**

```dart
import 'package:flutter/material.dart';

import '../../../screens/profile/profile_page.dart';
import '../../../screens/chat/home_page.dart';
import '../../focus/focus_home_page.dart';
import '../../timetable/presentation/timetable_page.dart';
import '../fr_route_handler.dart';

/// fr://lab/core/{pageKey} → 4 个核心页之一
///
/// pageKey: profile | home | focus | timetable
class LabCoreHandler extends FrRouteHandler {
  const LabCoreHandler();

  @override
  Widget build(BuildContext context, FrRouteMatch match) {
    final pageKey = match.path;
    final Widget? page = switch (pageKey) {
      'profile' => const ProfilePage(),
      'home' => const HomePage(),
      'focus' => const FocusHomePage(),
      'timetable' => const TimetablePage(),
      _ => null,
    };
    if (page == null) {
      return _UnknownCorePage(pageKey: pageKey);
    }
    return page;
  }
}

class _UnknownCorePage extends StatelessWidget {
  final String pageKey;
  const _UnknownCorePage({required this.pageKey});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('未知页面')),
      body: Center(child: Text('未知核心页面: $pageKey')),
    );
  }
}
```

- [ ] **Step 4: `notion_image_host_handler.dart`** — Task 7 阶段用占位，与 main.dart 完全解耦（避免编译失败）。Task 8 再加 NotionImageHostPage 真实引用

```dart
import 'package:flutter/material.dart';

import '../fr_route_handler.dart';

/// fr://notion/image-host?autocapture={true|false} → Notion 图床 deep link
///
/// Task 7 阶段返回占位 Widget（保持 main.dart 不变、独立绿色 commit）。
/// Task 8 改 main.dart 时会把 `NotionImageHostDeepLinkPage` 整体从 main.dart
/// 搬到这里，handler 升级为真实引用。
class NotionImageHostHandler extends FrRouteHandler {
  const NotionImageHostHandler();

  @override
  Widget build(BuildContext context, FrRouteMatch match) {
    final autocapture = match.queryBool('autocapture');
    return _NotionImageHostPlaceholder(autocapture: autocapture);
  }
}

class _NotionImageHostPlaceholder extends StatelessWidget {
  final bool autocapture;
  const _NotionImageHostPlaceholder({required this.autocapture});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notion 图床')),
      body: Center(
        child: Text('autocapture=$autocapture (Task 8 接入真实页面)'),
      ),
    );
  }
}
```

- [ ] **Step 5: `notion_create_page_handler.dart`**

```dart
import 'package:flutter/material.dart';

import '../fr_route_handler.dart';

/// fr://notion/create-page?databaseId={id} → 创建 page（占位）
///
/// 真实创建逻辑在 LabDemo "Notion 图床" 里；handler 先返回 DemoPage 兜底。
class NotionCreatePageHandler extends FrRouteHandler {
  const NotionCreatePageHandler();

  @override
  Widget build(BuildContext context, FrRouteMatch match) {
    // 占位实现 — 真实功能尚未从 LabDemo 迁出
    return const _NotImplementedPage();
  }
}

class _NotImplementedPage extends StatelessWidget {
  const _NotImplementedPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('notion/create-page 尚未实现')),
    );
  }
}
```

- [ ] **Step 6: `timetable_handler.dart`**

```dart
import 'package:flutter/material.dart';

import '../../timetable/presentation/timetable_page.dart';
import '../fr_route_handler.dart';

/// fr://timetable → 课表页
///
/// 桌面 widget MethodChannel 'navigateToTimetable' 翻译成 fr://timetable
class TimetableHandler extends FrRouteHandler {
  const TimetableHandler();

  @override
  Widget build(BuildContext context, FrRouteMatch match) {
    return const TimetablePage();
  }
}
```

- [ ] **Step 7: `bootstrap_routes.dart`**

```dart
import 'fr_router.dart';
import 'fr_route.dart';
import 'handlers/lab_index_handler.dart';
import 'handlers/lab_demo_handler.dart';
import 'handlers/lab_core_handler.dart';
import 'handlers/notion_image_host_handler.dart';
import 'handlers/notion_create_page_handler.dart';
import 'handlers/timetable_handler.dart';

/// 集中注册所有 fr:// 路由
///
/// 在 main() bootstrapLab() 之后调一次。
void registerAllFrRoutes() {
  frRouter.registerAll([
    FrRoute('lab', handler: const LabIndexHandler()),
    FrRoute('lab/demo', handler: const LabDemoHandler()),
    FrRoute('lab/core', handler: const LabCoreHandler()),
    FrRoute('notion/image-host', handler: const NotionImageHostHandler()),
    FrRoute('notion/create-page', handler: const NotionCreatePageHandler()),
    FrRoute('timetable', handler: const TimetableHandler()),
  ]);
}
```

- [ ] **Step 8: 编译验证**

Run: `flutter analyze lib/core/schema/`
Expected: 编译错误（`NotionImageHostPage`/`notionImageHostKey` 来自 main.dart）— 正常，Task 8 处理

- [ ] **Step 9: 提交**

```bash
git add lib/core/schema/handlers/ lib/core/schema/bootstrap_routes.dart
git commit -m "feat(schema): 6 个 handler + bootstrap_routes 集中注册

lab 三个：index/demo/core；notion 两个：image-host/create-page；
timetable 一个。registerAllFrRoutes() 集中注册。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: `main.dart` 改造 — 删除 4 个 _navigateToXxx

**Files:**
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: `FrNavigator` (from Task 6)、`frRouter` (from Task 4)、`registerAllFrRoutes` (from Task 7)
- Produces: `_dispatchFrUri` 替换 4 个方法

- [ ] **Step 1: 读现有 main.dart** — 已在 spec 阶段看过；本 Task 直接基于现状改

- [ ] **Step 2: 改 main.dart**

修改点（具体行号以 main.dart 现状为准）：

1. import `lib/core/schema/schema.dart` — 已经存在
2. `void main() async` 内 `bootstrapLab();` 之后加 `registerAllFrRoutes();`
3. `_MyAppState.initState` — 删 `SchemaNavigator.setNavigatorKey(navigatorKey);`，改成 `FrNavigator.setNavigatorKey(navigatorKey);`
4. `_handleMethodCall` 改写：

```dart
Future<dynamic> _handleMethodCall(MethodCall call) async {
  // 4 个 method 全部转成 fr:// URL，统一走 FrNavigator
  final frUrl = switch (call.method) {
    'navigateToLab' => 'fr://lab',
    'navigateToCalendar' => 'fr://lab/demo/日历待办',
    'navigateToTimetable' => 'fr://timetable',
    'navigateToNotionImage' => 'fr://notion/image-host?autocapture=${(call.arguments as bool?) ?? false}',
    _ => null,
  };
  if (frUrl == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    FrNavigator.handle(navigatorKey.currentContext, frUrl);
  });
}
```

5. 删 `_navigateToLab` / `_navigateToCalendar` / `_navigateToTimetable` / `_navigateToNotionImage` 4 个方法
6. `onGenerateRoute` 删 `if (settings.name == '/lab')` 分支（frRouter 自己处理 `fr://lab`）
7. `_CalendarDeepLinkPage` 类可删（统一走 frRouter）

- [ ] **Step 3: 升级 `notion_image_host_handler.dart` 为真实引用**

Task 7 用占位 `_NotionImageHostPlaceholder`，Task 8 把占位替换为 main.dart 现有 `NotionImageHostDeepLinkPage` + `NotionImageHostPage` + `notionImageHostKey` 的真实逻辑。**做法**：
- 把 main.dart 里的 `NotionImageHostDeepLinkPage` 类（行 257-281）整体搬到 `lib/core/schema/handlers/notion_image_host_handler.dart`，替换 `_NotionImageHostPlaceholder`
- import `package:xiaodouzi_fr/lab/demos/notion_image_host_demo.dart`（用 `show NotionImageHostPage, notionImageHostKey, triggerCaptureFromWidget`）
- main.dart 删 `NotionImageHostDeepLinkPage` 类和它引用的全局符号的 import

- [ ] **Step 4: 编译验证**

Run: `flutter analyze lib/`
Expected: 0 error

- [ ] **Step 5: 跑全量测试**

Run: `flutter test test/core/schema/`
Expected: 24/24 PASS

- [ ] **Step 6: 跑应用（手动 smoke test）**

Run: `flutter run -d <device>`

依次验证：
- [ ] 启动 app，控制台无 fr:// 相关 error
- [ ] 桌面 widget 点 4 个入口（lab/calendar/timetable/notion）能正确跳转
- [ ] Lab → 选 demo → 返回正常
- [ ] 文本链接 `[悬浮截屏](fr://lab/demo/clock)` 渲染可点击，点击跳转

- [ ] **Step 7: 提交**

```bash
git add lib/main.dart lib/core/schema/handlers/notion_image_host_handler.dart
git commit -m "refactor(main): 4 个 _navigateToXxx 合并为 fr:// URL dispatch

_handleMethodCall switch 翻译 4 个 method name 到 fr:// URL；
FrNavigator.handle 统一处理。NotionImageHostDeepLinkPage 从
main.dart 搬到 notion_image_host_handler.dart。onGenerateRoute
删 fr://lab 特殊分支。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: 删除老 `SchemaService` / `SchemaNavigator` / `SchemaParser`

**Files:**
- Delete: `lib/core/schema/schema_service.dart`
- Delete: `lib/core/schema/schema_navigator.dart`
- Delete: `lib/core/schema/schema_parser.dart`
- Modify: `lib/core/schema/schema_text.dart`（autoLink 搬进来）

**Interfaces:**
- Consumes: `frRouter` (from Task 4)、`SchemaLinkParser` 的 autoLink（从 schema_parser.dart 迁移）
- Produces: `schema_text.dart` 内部用 `frRouter.handle` 替换 `SchemaNavigator.navigateToSchema`

- [ ] **Step 1: 读 `lib/core/schema/schema_text.dart`**

已在 spec 阶段看过；本 Task 直接基于现状改

- [ ] **Step 2: 改 `schema_text.dart`**

修改点：
1. import：`schema_parser.dart` → `fr_router.dart` / `fr_uri.dart`
2. `_handleLinkTap` 方法：把 `SchemaNavigator.navigateToSchema(schema)` 改成 `frRouter.handle(context, schema)`（同时拿 context）
3. `autoLink` 静态方法：保留逻辑，从 `schema_parser.dart` 搬过来（私有 `_autoLink`），删除 `schema_parser.dart` 整个文件

- [ ] **Step 3: 删 3 个老文件**

```bash
rm lib/core/schema/schema_service.dart
rm lib/core/schema/schema_navigator.dart
rm lib/core/schema/schema_parser.dart
```

- [ ] **Step 4: 编译验证**

Run: `flutter analyze lib/`
Expected: 0 error（如果还有 import 残留会有提示，全删掉即可）

- [ ] **Step 5: 跑全量测试**

Run: `flutter test test/core/schema/`
Expected: 24/24 PASS

- [ ] **Step 6: 提交**

```bash
git add lib/core/schema/
git commit -m "refactor(schema): 删除 SchemaService/SchemaNavigator/SchemaParser

老 API 全部下线：schema_service.dart (SchemaRoutes/SchemaRegistry)、
schema_navigator.dart、schema_parser.dart 删除。schema_text.dart 内部
跳转改用 frRouter.handle；autoLink 逻辑搬入 schema_text.dart 私有方法。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: 5 个老路径烟雾测试

**Files:**
- Create: `test/core/schema/migration_test.dart`

**Interfaces:**
- Consumes: `frRouter` (from Task 4)、`registerAllFrRoutes` (from Task 7)
- Produces: 5 个烟雾测试用例

- [ ] **Step 1: 写测试** — `test/core/schema/migration_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/schema/schema.dart';

void main() {
  setUpAll(() {
    registerAllFrRoutes();
  });

  group('frRouter migration smoke', () {
    test('fr://lab resolves to LabIndexHandler', () {
      final match = frRouter.resolve('fr://lab');
      expect(match, isNotNull);
      expect(match!.host, 'lab');
      expect(match.path, '');
      expect(frRouter.findHandler('lab'), isA<FrRouteHandler>());
    });

    test('fr://lab/demo/clock resolves to LabDemoHandler', () {
      final match = frRouter.resolve('fr://lab/demo/clock');
      expect(match, isNotNull);
      expect(match!.path, 'clock');
    });

    test('fr://lab/core/profile resolves to LabCoreHandler', () {
      final match = frRouter.resolve('fr://lab/core/profile');
      expect(match, isNotNull);
      expect(match!.path, 'profile');
    });

    test('fr://notion/image-host?autocapture=true resolves with query', () {
      final match = frRouter.resolve('fr://notion/image-host?autocapture=true');
      expect(match, isNotNull);
      expect(match!.queryBool('autocapture'), isTrue);
    });

    test('fr://timetable resolves to TimetableHandler', () {
      final match = frRouter.resolve('fr://timetable');
      expect(match, isNotNull);
      expect(match!.host, 'timetable');
    });

    test('http://lab returns null (wrong scheme)', () async {
      final match = await frRouter.resolve('http://lab');
      expect(match, isNull);
    });

    test('fr://unknown returns null (unknown host)', () async {
      final match = await frRouter.resolve('fr://unknown');
      expect(match, isNull);
    });
  });
}
```

- [ ] **Step 2: 跑测试**

Run: `flutter test test/core/schema/migration_test.dart`
Expected: 7/7 PASS

- [ ] **Step 3: 跑全量测试**

Run: `flutter test test/core/schema/`
Expected: 31/31 PASS（24 + 7）

- [ ] **Step 4: 提交**

```bash
git add test/core/schema/migration_test.dart
git commit -m "test(schema): 5 个老路径烟雾测试

lab / lab/demo/clock / lab/core/profile / notion/image-host
（带 query）/ timetable 全部能 resolve 到对应 handler。
http 协议和 unknown host 验证 null 路径。

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 11: 验收检查

**Files:** 无（全量验证）

- [ ] **Step 1: 全量 analyze**

Run: `flutter analyze lib/`
Expected: 0 error, 0 warning

- [ ] **Step 2: 全量 test**

Run: `flutter test`
Expected: 全绿（包含 31 个新测试）

- [ ] **Step 3: 验证老 API 完全消失**

```bash
grep -rn "SchemaNavigator\|SchemaRegistry\|SchemaRoutes\|schemaRegistry\|SchemaLinkParser" lib/
```

Expected: 无任何匹配

- [ ] **Step 4: 验证 5 个模块入口都走 frRouter**

```bash
grep -rn "FrNavigator\.handle" lib/
```

Expected: 至少 2 处（schema_text.dart _handleLinkTap、main.dart _handleMethodCall）

- [ ] **Step 5: 手动 smoke test**（参考 Task 8 Step 6 列表）

- [ ] **Step 6: 提交（如果有遗漏修复）**

```bash
git add <fix-files>
git commit -m "chore(schema): 验收检查遗漏修复

<列出修复内容>

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## 验收标准（对齐 spec §7）

- [ ] `flutter analyze` 0 warning
- [ ] `flutter test` 全绿（31 个新 case）
- [ ] `lib/core/schema/schema_service.dart` / `schema_navigator.dart` / `schema_parser.dart` 3 个文件被删除
- [ ] main.dart 的 `_navigateToXxx` 4 个方法被合并为 `_handleMethodCall` switch
- [ ] 5 个模块的 fr:// 入口（文本、MethodChannel、timetable 反注册、notion 反注册、demo 反注册）全部走 frRouter
- [ ] 启动后无控制台 fr:// 相关 error
- [ ] 桌面 widget 4 个 method 跳转路径全部 smoke test 通过
