# fr:// 内部 URL 路由中心化重构

> **状态**：待审核
> **日期**：2026-07-03
> **范围**：`lib/core/schema/` 升级为路由中心；删除老 `SchemaNavigator` / `SchemaRegistry` 静态类；统一 5 个模块的 fr:// 入口；main.dart 的 MethodChannel 反注册也走同一分发器。一次性彻底迁移，老 API 全部删除。

---

## 1. 目标

把分散在 5 个模块的 fr:// 内部 URL 处理收敛到**一个注册中心**：任何来源（文本链接、MethodChannel 反注册、Shortcut、内部代码调用）都走同一份路由表，新增页面只在一处注册。

### 不做什么

- ❌ **不引入第三方路由库**（go_router、auto_route 都不引；当前 200+ 处 Navigator.push 不能被破坏）
- ❌ **不改 demo 渲染层**（`buildPage(BuildContext)` 签名不变；demos 不感知 fr:// 的存在）
- ❌ **不改 lab_bootstrap.dart 的注册流程语义**（仍按 title 索引到 demo；只是内部多注册一份 fr:// 路由）
- ❌ **不重写 MethodChannel 协议**（`io.github.xiaodouzi.fr/widget` 的 4 个 method 名字保留）
- ❌ **不做权限/中间件系统**（YAGNI；如需后续加 hook 链）

## 2. 动机

### 当前腐蚀（5 处入口不一致）

| 位置 | 行为 | 重复/问题 |
|---|---|---|
| `core/schema/schema_service.dart` | `_registerCorePages()` 硬编码 4 个 core page | 与 `schema_navigator.dart` 的 switch case 重复 |
| `core/schema/schema_navigator.dart` | 4 个 if/else + 4 个 switch case；`setNavigatorKey` 静态全局 | 加新核心页要改 2 处 |
| `main.dart` | 4 个 `_navigateToXxx` 平行存在；硬编码 demo key `'Notion 图床'` / `'日历待办'` | 与 schema 层平行存在，无统一入口 |
| `lab/demos/*_demo.dart` | 36 个 demo 用 `demoRegistry.register(WidgetClass())` | 正常，但 demo key 与 fr:// 路由映射在 `SchemaRegistry.discover()` 里二次生成 |
| `services/message_strategy/text_link_message_strategy.dart` | 复用 `SchemaText`，依赖 SchemaNavigator | 链路长、错位难追 |

**反注册语义**：用户提到 "api/notion/file_endpoint.dart" 和 "core/timetable" 是 fr:// **反向**调用入口 —— Notion 上传完图片需要打开 fr://notion/image-host，桌面 widget 点击需要 fr://lab/core/timetable。这些都已经在 main.dart 的 `_handleMethodCall` 处理，但是分散的、与 schema 平行。

### 痛点示例

加一个新的核心页（比如"设置"）要改：
1. `schema_service.dart` 的 `_registerCorePages` 加一个 `SchemaEntry`
2. `schema_navigator.dart` 的 `navigateToCorePage` switch 加一个 case
3. `lab_bootstrap.dart` 不需要改（因为不在 demo 列表）
4. 如果桌面 widget 也要能跳转，main.dart 加一个 `_navigateToSettings` + MethodChannel handler

**修后只改 1 处**：注册一个 `SettingsRouteHandler`。

## 3. 设计

### 3.1 URI 语法

```
fr://{host}/{path?}?{query?}
```

- `scheme` 固定 `fr`
- `host` 是路由命名空间（lab / notion / timetable / profile / focus / home）
- `path` 可选；可有可无、可多段
- `query` 可选；`?key=value&key2=value2`；value 自动 decode

**示例**：
- `fr://lab` → host=lab, path=""
- `fr://lab/demo/clock` → host=lab, path="demo/clock"
- `fr://notion/image-host?autocapture=true` → host=notion, path="image-host", query={autocapture: true}
- `fr://notion/create-page?databaseId=38b550be-...` → host=notion, path="create-page", query={databaseId: ...}

### 3.2 组件拓扑

```
lib/core/schema/
├── fr_uri.dart              ← URI 解析（scheme/host/path/query 拆分）
├── fr_route.dart            ← 路由条目（host + handler 引用）
├── fr_route_handler.dart    ← 抽象基类 + 工具方法（queryString/queryBool/pathSegment）
├── fr_router.dart           ← 单例注册中心（register/registerAll/handle）
├── fr_navigator.dart        ← 替换原 SchemaNavigator（基于 frRouter 实现）
└── schema_text.dart         ← 保留：改用 frRouter 内部跳转
```

`schema.dart` 改成 `export 'fr_router.dart'; export 'fr_navigator.dart'; export 'schema_text.dart';` —— 旧 `schemaRegistry` / `SchemaRoutes` 不再导出。

### 3.3 数据流

```
   3 个入口
   ┌─ 文本: SchemaText.onLinkTap ──────────────┐
   ├─ MethodChannel: main.dart 4 个 _navigateXxx ┤
   └─ 内部: frRouter.handle(ctx, url) ─────────┘
                    │
                    ▼
        ┌─────────────────────┐
        │ frRouter.handle()   │  ← 单例，找 host 匹配
        └─────────┬───────────┘
                  ▼
        ┌─────────────────────┐
        │ FrRouteHandler.build│  ← handler 拿 query/path params
        └─────────┬───────────┘  返回 Widget
                  ▼
        Navigator.push(MaterialPageRoute)
                  │
                  ▼
        错误: SnackBar(错误消息) + debugPrint
```

### 3.4 注册 API

```dart
// 一次性注册（在 lib/core/schema/bootstrap_routes.dart，main() 之前调）
void registerAllFrRoutes() {
  frRouter.registerAll([
    FrRoute('lab',           handler: const LabIndexHandler()),
    FrRoute('lab/demo',      handler: const LabDemoHandler()),
    FrRoute('lab/core',      handler: const LabCoreHandler()),
    FrRoute('notion/image-host', handler: const NotionImageHostHandler()),
    FrRoute('notion/create-page', handler: const NotionCreatePageHandler()),
    FrRoute('timetable',     handler: const TimetableHandler()),
  ]);
}
```

### 3.5 Handler API

```dart
// 基类
abstract class FrRouteHandler {
  const FrRouteHandler();
  Widget build(BuildContext context, FrRouteMatch match);
}

// 工具方法（FrRouteMatch 上）
class FrRouteMatch {
  final String host;
  final String path;          // "" 或 "demo/clock"
  final Map<String, String> query;

  String? queryString(String key) => query[key];
  bool queryBool(String key, {bool defaultValue = false}) {
    final v = query[key];
    if (v == null) return defaultValue;
    return v == 'true' || v == '1';
  }
  String pathSegment(int index) { /* 拆 path 按 '/' */ }
}
```

### 3.6 handler 实现示例

```dart
class NotionImageHostHandler extends FrRouteHandler {
  const NotionImageHostHandler();
  @override
  Widget build(BuildContext context, FrRouteMatch match) {
    final autocapture = match.queryBool('autocapture');
    return NotionImageHostDeepLinkPage(autocapture: autocapture);
  }
}

class LabDemoHandler extends FrRouteHandler {
  const LabDemoHandler();
  @override
  Widget build(BuildContext context, FrRouteMatch match) {
    final demoKey = match.path;  // e.g. "clock"
    final demo = demoRegistry.get(demoKey);
    if (demo == null) {
      _showError(context, '未找到 Demo: $demoKey');
      return const SizedBox.shrink();
    }
    return _DemoDetailPage(demo: demo);
  }
}
```

### 3.7 错误处理

| 错误 | 表现 |
|---|---|
| scheme 非 `fr://` | `debugPrint` + 静默返回 |
| 找不到 host | SnackBar "未知路由: {host}" |
| handler 返回 null | 静默 debugPrint（防御） |
| handler 抛异常 | SnackBar 显示 e.message + debugPrint stacktrace |
| context.mounted=false | 跳过 push，记录日志 |
| NavigatorState 为 null | debugPrint + 静默返回（保留老 SchemaNavigator 行为） |

## 4. 迁移计划

### 4.1 删除

- `lib/core/schema/schema_service.dart`（SchemaRoutes / SchemaRegistry / schemaRegistry）
- `lib/core/schema/schema_parser.dart`（保留 autoLink 静态方法 → 移到 schema_text.dart 内私有）
- `lib/core/schema/schema_navigator.dart`（重写为 fr_navigator.dart，零旧 API）
- `lib/lab/lab_container.dart` 中的 `DemoRegistry` / `demoRegistry`（保留 `DemoPage` 抽象类）

### 4.2 新增

- `lib/core/schema/fr_uri.dart`
- `lib/core/schema/fr_route.dart`
- `lib/core/schema/fr_route_handler.dart`
- `lib/core/schema/fr_router.dart`
- `lib/core/schema/fr_navigator.dart`
- `lib/core/schema/bootstrap_routes.dart`
- `lib/core/schema/handlers/lab_index_handler.dart`
- `lib/core/schema/handlers/lab_demo_handler.dart`
- `lib/core/schema/handlers/lab_core_handler.dart`
- `lib/core/schema/handlers/notion_image_host_handler.dart`
- `lib/core/schema/handlers/notion_create_page_handler.dart`
- `lib/core/schema/handlers/timetable_handler.dart`

### 4.3 修改

- `lib/main.dart`
  - 删 `_navigateToLab` / `_navigateToCalendar` / `_navigateToTimetable` / `_navigateToNotionImage` 4 个方法
  - `_handleMethodCall` 改用 frRouter 翻译
  - `onGenerateRoute` 删 fr://lab 特殊分支（router 自己处理）
- `lib/core/schema/schema_text.dart`
  - `_handleLinkTap` 改用 frRouter.handle
  - `autoLink` 私有化（仅 lab demo 用）
- `lib/core/schema/schema.dart`
  - export 调整
- `lib/lab/lab_bootstrap.dart`
  - `bootstrapLab()` 加 `registerAllFrRoutes()` 调用
- `lib/services/message_strategy/strategies/text_link_message_strategy.dart`
  - 不动（仍然用 SchemaText，链路自洽）

## 5. 测试覆盖

- `test/core/schema/fr_uri_test.dart`（约 8 cases）
  - 基础 scheme 校验
  - host 提取
  - path 多段拆
  - query 解析 + 中文 URL decode
  - 空 query / 空 path 边界
  - 错误 scheme 抛 / 静默（看实现）
- `test/core/schema/fr_router_test.dart`（约 6 cases）
  - 单条注册 + handle
  - registerAll 批量注册
  - 未知 host 错误路径
  - query 透传到 handler
  - handler 异常捕获
- `test/core/schema/fr_route_handler_test.dart`（约 5 cases）
  - queryString / queryBool 默认值
  - pathSegment 越界
  - 多段 path
- `test/core/schema/migration_test.dart`（约 6 cases，烟雾测试）
  - `fr://lab` → LabIndexHandler
  - `fr://lab/demo/clock` → LabDemoHandler + demoRegistry 查询
  - `fr://lab/core/profile` → LabCoreHandler + ProfilePage
  - `fr://notion/image-host?autocapture=true` → NotionImageHostHandler
  - `fr://timetable` → TimetableHandler
  - 错误 url（无 fr://）静默

**总计**：约 25 个单元测试。不写 widget 测试。

## 6. 风险与回滚

| 风险 | 缓解 |
|---|---|
| 老 `SchemaNavigator` / `schemaRegistry` 删除后漏改 | grep + flutter analyze；spec 第 4.3 列所有修改点 |
| 36 个 demo 的 title 有中文/特殊字符，demoRegistry get 不到 | 沿用现有行为；`demoRegistry.get('Notion 图床')` 已经在 main.dart 验证过 |
| MethodChannel 反注册链路断 | 保留 4 个 method 名，只改内部调用 |
| 路由表循环依赖 | handler 文件不 import 任何 lab_bootstrap 内容；handler 内只调 demoRegistry.get / 构造 Widget |
| 中文 host 段在某些 Flutter 版本有 UTF-8 问题 | host 段强制要求 ASCII（lab/notion/timetable/profile/focus/home），中文仅出现在 path（已验证 `_unescape`） |

**回滚**：单 commit 删除 + 新增 → 回滚即一个 revert。

## 7. 验收标准

- [ ] `flutter analyze` 0 warning
- [ ] `flutter test` 全绿（含新增 25 个 case）
- [ ] `lib/core/schema/schema_service.dart` 文件被删除
- [ ] `lib/core/schema/schema_navigator.dart` 旧 API 不再导出
- [ ] main.dart 的 `_navigateToXxx` 4 个方法被删除或合并为 1 个
- [ ] 5 个模块的 fr:// 入口（文本、MethodChannel、timetable 反注册、notion 反注册、demo 反注册）全部走 frRouter
- [ ] 启动后无控制台 fr:// 相关 error
- [ ] 桌面 widget 4 个 method 跳转路径全部 smoke test 通过
