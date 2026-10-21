---
name: A01-fr路由注册与防腐蚀
description: FR `fr://` 页面路由注册、MethodChannel 翻译与路由完整性检查。新增可深链页面或原生跳转时读取。
---

# A01 — FR `fr://` 路由注册与防腐蚀

> 适用范围：仅适用于 FR 仓库。路由设计、URI 解析和 prefix 匹配原理见 [[A02-fr-Router路由机制]]。本 ref 讲日常注册、入口统一和验证。

## 何时使用 `fr://`

一个页面需要从文本链接、桌面 widget、通知、外部 Intent 或多个不同入口打开时，应注册 `fr://` handler。只在单一流程里由一个按钮打开的一次性子页，不因“页面存在”就必须新建 deep link；沿用模块原有 Navigator/route 模式即可。

## 新页面注册流程

1. 在 `lib/core/schema/handlers/` 为外部可路由目标实现 `FrRouteHandler`。
2. 在 `lib/core/schema/bootstrap_routes.dart` 的集中路由列表注册 `FrRoute`；检查 authority/key 不与已有路由冲突。
3. 写 `FrRouter.resolve()` 测试：断言具体 handler 类型、匹配 authority/path 边界和关键 query 行为，不只断言 `isNotNull`。
4. 若 Android/widget/native 要触发该页面：
   - Android 侧 method/Intent/data 与 `lib/app_lifecycle/fr_method_channel_translator.dart` 的 method 名和转换目标对应。
   - 新 destination 仍须注册 handler；translator 只做 method → URL 翻译，不会自动注册 route。
   - 确认 `MainActivity` 的 Intent path 能将深链交给 Flutter，再验证一次完整 native → translator → FrNavigator → handler 流程。

```dart
class SettingsHandler extends FrRouteHandler {
  const SettingsHandler();

  @override
  Widget build(BuildContext context, FrRouteMatch match) => const SettingsPage();
}
```

```dart
// bootstrap_routes.dart
FrRoute('settings', handler: const SettingsHandler()),
```

新 MethodChannel method 应加在 `FrMethodChannelTranslator.translate()` 的 switch 中；main.dart 负责调用 translator，不直接维护另一份 method→page 映射。

## 三种调用方式

- **富文本**：`SchemaText('[时钟](fr://lab/demo/clock)')`，点击进入 `FrNavigator.handle`。
- **项目内 deep link 按钮**：`FrNavigator.handle(context, 'fr://lab/demo/clock')`。
- **Android/widget**：Kotlin `invokeMethod` 或 Intent 按当前 widget 规范进入 MainActivity，再由 translator/router 统一派发。

三种 `fr://` 入口的目标应一致。仅流程内部的非 deep-link 页面可使用本地 Navigator；不要让同一个外部可达页面同时维护互不一致的直达页面分支。

## 路由完整性检查

在仓库根执行路由改动对应的检查；`rg`/grep 搜索只负责发现候选，仍需人工区分测试、注释和合理内部导航，不将搜索结果视为自动 CI 判定。

```bash
# widget/页面是否自行解析 fr://
rg -n "startsWith.*fr://" lib/ -g '*.dart'

# handlers 是否反向依赖 main.dart
rg -n "import.*main.dart" lib/core/schema/handlers/ -g '*.dart'

# Android method 名和 Dart 翻译表是否对齐
rg -n "invokeMethod" android/app/src/main/kotlin/
rg -n "=> 'fr://" lib/app_lifecycle/fr_method_channel_translator.dart

# 检查旧 schema API（人工判断注释/历史记录）
rg -n "SchemaNavigator|SchemaRegistry|SchemaRoutes|schemaRegistry" lib/

# Demo slug 纯 ASCII 与注册约束
dart test test/lab/demo_slug_test.dart
```

完成路由改动后，检查测试 exit code 和输出；若目标页面同时有 Android/widget 入口，再通过相关设备或集成流程验证 Intent、Channel、translator、route 连通。

## 防腐蚀信号

| 现象 | 风险 | 下一步 |
|---|---|---|
| widget 中按 URL `startsWith` 自己分发 | 路由逻辑离开 Router，新增入口容易漏改 | 将 deep link 交给 `FrNavigator.handle`；运行 A02 的 prefix 匹配测试 |
| Android method 有调用但 translator 无映射 | native method 无统一 URL 目标 | 对照 Kotlin method 名，在 translator 增加明确映射，并验证 MainActivity 调用链 |
| 外部可达页面只在某处直接 `Navigator.push` | 文本/通知/widget 路径行为不一致 | 注册 handler，更新外部入口统一 URL；单流程内部子页保留局部导航即可 |
| Handler import `main.dart` | 容易形成应用入口循环依赖 | 让 handler 直接依赖目标 Page 或小型 navigation service |
| 路由未进入 bootstrap 注册列表 | URL 找不到 handler | 添加集中注册和具体类型 resolve 测试 |
| 路由 key 冲突/前缀重叠 | 请求可能命中非预期 handler | 对照 A02 的最长前缀和 slash boundary 规则，加冲突测试 |
| demo URL 使用中文 title | URL 不稳定、外部链接难维护 | 使用 co-located ASCII canonical slug；解析器虽对原始中文容错，也不要把 UI 标题当协议 key |

## 相关 ref

- Router 解析/匹配/handler 设计：[[A02-fr-Router路由机制]]。
- Demo canonical slug 与 alias：[[A06-Demo-Slug别名]]。
- Lab 新 Demo 的注册与容器约束：[[A03-Lab容器结构与扩展]]。
- Android/widget Intent 与 channel 链路：[[G00-Android与Native路由]]。
