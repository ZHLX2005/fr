# Flutter fr:// 路由注册规范与防腐蚀

> **与设计 ref 的关系**：`Flutter-自定义Scheme路由中心化-fr-Router.md` 讲**为什么**这么设计 + 设计陷阱（authority/path 拆分、prefix 匹配）。本 ref 讲**日常怎么用**：加新页面、用 fr:// 跳转、防止代码腐蚀。
>
> - 要理解路由系统 / 重构路由 → 读**设计 ref**
> - 要加新页面 / 写跳转 / 提交前自查 → 读**本 ref**

---

## 新页面注册 SOP

### 场景 A：纯 Flutter 内部页面（不需要 native 唤起）

**3 步**：

1. **写 handler** — `lib/core/schema/handlers/xxx_handler.dart`
2. **注册** — `bootstrap_routes.dart` 加一行 `FrRoute('xxx', handler: const XxxHandler())`
3. **测试** — 断言**具体 handler 类型**（不能只断言非 null，见设计 ref）

```dart
// 1. handler
class SettingsHandler extends FrRouteHandler {
  const SettingsHandler();
  @override
  Widget build(BuildContext context, FrRouteMatch match) {
    return const SettingsPage();
  }
}

// 2. bootstrap_routes.dart 的 registerAllFrRoutes() 内加一行
FrRoute('settings', handler: const SettingsHandler()),

// 3. test/core/schema/migration_test.dart 加
test('fr://settings resolves to SettingsHandler', () async {
  final match = await frRouter.resolve('fr://settings');
  expect(match, isNotNull);
  expect(frRouter.findHandler(match!.authority), isA<SettingsHandler>());
});
```

### 场景 B：需要从桌面 widget / native 唤起

在场景 A 的 3 步之上，**额外 2 步**：

4. **main.dart 翻译 MethodChannel** — `_handleMethodCall` switch 加一个 case
5. **Android 端** widget 的 `PendingIntent` / `MethodChannel` 调用对应 method

```dart
// 4. main.dart _handleMethodCall
'navigateToSettings' => 'fr://settings',

// 5. Android Kotlin（widget provider 或 service）
methodChannel.invokeMethod("navigateToSettings")
```

> **不要**在 main.dart 里直接 `Navigator.push(SettingsPage())` —— 那样就绕过了路由表，桌面 widget 路径和文本链接路径就不统一了。

---

## 使用 fr:// 的 3 种方式

### 1. 文本内嵌链接（用户可见的富文本）

```dart
SchemaText('点击 [时钟](fr://lab/demo/时钟) 看看');
```

`SchemaText` 自动解析 `[文字](fr://...)` 格式，点击走 `FrNavigator.handle`。

### 2. 内部代码跳转（按钮 onTap、卡片点击等）

```dart
onTap: () => FrNavigator.handle(context, 'fr://lab/demo/clock');

// 带参数
onTap: () => FrNavigator.handle(
  context,
  'fr://notion/image-host?autocapture=true',
);
```

### 3. MethodChannel 反注册（native → Flutter）

```kotlin
// Android Kotlin
methodChannel.invokeMethod("navigateToTimetable")
```

```dart
// main.dart _handleMethodCall 翻译
'navigateToTimetable' => 'fr://timetable',
```

> 三种方式最终都汇入 `FrNavigator.handle` → `frRouter.resolve` → `handler.build` → `nav.push`。**这是统一性的保证**。

---

## ⚠️ 防腐蚀：什么算"自己设置造成腐蚀"

| 腐蚀信号 | 说明 | 后果 |
|---|---|---|
| 在 widget 里写 `if (url.startsWith('xxx'))` 自己分发 | 绕过 router | 路由表失真，新增页面时找不到这里 |
| 新增 MethodChannel method 但不在 `_handleMethodCall` 翻译 | native 直连页面 | 文本链接和 native 跳转行为不一致 |
| 用 `Navigator.push(MaterialPageRoute(...))` 直接跳页面 | 绕过 FrNavigator | 丢失防重复 push 保护，返回手势多重折叠 |
| handler 里 `import '../../../main.dart'` | 循环依赖 | 编译可能挂；main 改动牵连 handler |
| `bootstrap_routes.dart` 漏注册新 handler | 路由孤立 | 运行时才发现，`fr://xxx` 静默失败 |
| 给路由键起名和现有 handler 冲突（如重复注册 `lab`） | 后注册覆盖先注册 | 旧路由静默失效 |

---

## 防腐蚀 grep 检测（提交前自查 / CI）

每次涉及路由改动，跑这 5 个 grep + 1 个 slug 测试自查：

```bash
# 1. 检查是否有绕过 router 的自己分发（widget 里手写 if/else）
grep -rn "startsWith.*fr://" lib/ | grep -v "fr_uri.dart\|fr_router.dart"
# 期望：0 处（fr:// 的 startsWith 只应出现在解析器里）

# 2. 检查 handler 不引用 main.dart（防循环依赖）
grep -rn "import.*main.dart" lib/core/schema/handlers/
# 期望：0 处

# 3. 检查 MethodChannel method 是否都翻译了
# 先看 Android 侧调了哪些 method
grep -rn "invokeMethod" android/app/src/main/kotlin/ | grep -oE '"[a-zA-Z]+"' | sort -u
# 再看 main.dart 是否每个都有对应 case
grep -n "=> 'fr://" lib/main.dart

# 4. 检查所有 Navigator.push 是否走 FrNavigator（例外要注释说明）
grep -rn "nav.push\|Navigator\.push\|MaterialPageRoute" lib/ \
  | grep -v "fr_navigator.dart\|main.dart.*_pushOnceIfNotOnTop\|// "
# 人工 review 每处是否有正当理由绕过

# 5. 检查老 API 残留（SchemaNavigator / SchemaRegistry 等）
grep -rn "SchemaNavigator\|SchemaRegistry\|SchemaRoutes\|schemaRegistry" lib/
# 期望：0 处（注释里的历史提及可接受，但要确认是注释不是代码）
```

```bash
# 6. 检查 demo 是否都有英文 slug（防中文 URL 崩溃，见设计 ref「中文 URL 陷阱」）
# 跑 demo_slug_test，它断言"全部 demo slug 纯 ASCII 无中文残留"
flutter test test/lab/demo_slug_test.dart
# 期望：全绿。新增 demo 漏写 `@override String get slug` 时**编译期**直接 fail（abstract 强制），
#       即使绕过编译，写中文 slug 也会被这里拦截。
```

---

## 新增路由 Checklist

加新 fr:// 路由时逐项确认：

- [ ] handler 文件在 `lib/core/schema/handlers/` 下
- [ ] handler 类名后缀 `Handler`，文件名后缀 `_handler.dart`（命名规范）
- [ ] `bootstrap_routes.dart` 已注册该路由
- [ ] 测试断言了**具体 handler 类型**（`isA<XxxHandler>()`）
- [ ] 如果是嵌套路由（`xxx/yyy/zzz`），测试覆盖了 slash 边界 case（见设计 ref）
- [ ] handler 不 import `main.dart`（引用目标 Page 而非 main）
- [ ] 如果走 MethodChannel，main.dart `_handleMethodCall` 已翻译
- [ ] 跑过上面的 6 项自查

**Demo 路由专属**（`fr://lab/demo/{slug}`）：

- [ ] 新 demo 的 slug 已在子类文件 `@override String get slug => 'xxx';` 声明（**不再**用 `kDemoSlugs` 全局表，slug 抽象化后该表已删除）
- [ ] slug 必须纯 ASCII（小写字母/数字/连字符），与中文 title 同文件 co-located
- [ ] URL 用 slug 不用 title（`fr://lab/demo/clock` ✅，`fr://lab/demo/时钟` ❌ 会崩溃）
- [ ] `test/lab/demo_slug_test.dart` 跑通（断言 slug 纯 ASCII + 别名一致性）
- [ ] 旧 slug 别名：通过 `demoRegistry.register(demo, key: 'legacy-slug')` 单独注册到同一实例，详见 [[Flutter-DemoPage-slug抽象化与别名机制]]

---

## 反模式（NOK Examples）

### NOK 1：在 widget 里自己 if/else 分发

```dart
// ❌ 错误：绕过 router
onTap: () {
  if (link.startsWith('fr://lab/demo/')) {
    final key = link.substring('fr://lab/demo/'.length);
    final demo = demoRegistry.get(key);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => DemoDetailPage(demo: demo),
    ));
  } else if (link.startsWith('fr://timetable')) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => const TimetablePage(),
    ));
  }
}

// ✅ 正确：一行走 router
onTap: () => FrNavigator.handle(context, link);
```

**为什么错**：这又把路由分发逻辑搬回 widget 层，正是本次重构要消除的腐蚀。新增路由时 widget 这里要改，路由表也失真。

### NOK 2：MethodChannel 直接连页面

```dart
// ❌ 错误：main.dart 直接 push，绕过路由表
Future<dynamic> _handleMethodCall(MethodCall call) async {
  if (call.method == 'navigateToSettings') {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pushOnceIfNotOnTop('settings', (_) => const SettingsPage());
    });
  }
}

// ✅ 正确：翻译成 fr:// URL，让 FrNavigator 统一处理
'navigateToSettings' => 'fr://settings',
// + bootstrap 注册 FrRoute('settings', handler: SettingsHandler())
```

**为什么错**：桌面 widget 走的是直连，文本链接走的是 frRouter，两条路径行为可能不一致（防重复 push、错误处理、query 参数）。

### NOK 3：handler 引用 main.dart

```dart
// ❌ 错误：循环依赖
// lib/core/schema/handlers/xxx_handler.dart
import '../../../main.dart';  // main 又 import schema/schema.dart → 循环
```

```dart
// ✅ 正确：handler 是 main 的下游，直接引用目标 Page
import '../../../screens/settings/settings_page.dart';
```

**为什么错**：Dart 循环 import 在某些情况下编译失败；main 改动会牵连所有 handler。

### NOK 4：测试只断言非 null

```dart
// ❌ 错误：嵌套路由错位时测试全绿但功能全错
test('fr://lab/demo/clock resolves', () async {
  final match = await frRouter.resolve('fr://lab/demo/clock');
  expect(match, isNotNull);  // 通过！但可能命中的是 LabIndexHandler
});

// ✅ 正确：断言具体类型 + 反向断言不是兄弟 handler
test('fr://lab/demo/clock resolves to LabDemoHandler', () async {
  final match = await frRouter.resolve('fr://lab/demo/clock');
  expect(match, isNotNull);
  expect(frRouter.findHandler(match!.authority), isA<LabDemoHandler>());
  expect(frRouter.findHandler(match.authority), isNot(isA<LabIndexHandler>()));
});
```

**为什么错**：本次重构的 critical bug（host 拆分错误导致嵌套路由全失效）就是藏在"只断言非 null"的测试里长达 9 个 Task。详见设计 ref。

### NOK 5：URL 直接用中文 demo title

```dart
// ❌ 错误：Uri.decodeComponent 对原始中文抛 Illegal percent encoding，
//         URL resolve 崩溃，跳转静默失败
'navigateToClock' => 'fr://lab/demo/时钟',
SchemaText('[时钟](fr://lab/demo/时钟)')

// ✅ 正确：用英文 slug（子类 `@override String get slug => 'xxx';`），显示文字仍可中文
'navigateToClock' => 'fr://lab/demo/clock',
SchemaText('[时钟](fr://lab/demo/clock)')   // 显示"时钟"，URL 是 clock
```

**为什么错**：`Uri.decodeComponent` 对原始中文字符串（非 `%E6...` 编码形式）抛 `Illegal percent encoding`，导致含中文的 fr:// URL 全部 resolve 崩溃。这是藏在 41 个绿测试里的生产 bug（测试用编码形式，生产用原始中文）。详见设计 ref「中文 URL 陷阱」。修复 = ASCII slug + safeDecode 双保险。

---

## 模板代码（复制即用）

### 新 handler 模板

```dart
import 'package:flutter/material.dart';
import '../fr_route_handler.dart';

/// fr://{authority} → {目标页面}
///
/// 注册：在 bootstrap_routes.dart 的 registerAllFrRoutes() 内加
///   FrRoute('{authority}', handler: const {Name}Handler()),
class {Name}Handler extends FrRouteHandler {
  const {Name}Handler();

  @override
  Widget build(BuildContext context, FrRouteMatch match) {
    // 如需 query 参数：
    //   final foo = match.queryString('foo');
    //   final flag = match.queryBool('flag', defaultValue: false);
    // 如需 path 段：
    //   final id = match.pathSegment(0);
    return const {TargetPage}();
  }
}
```

### 新测试模板

```dart
test('fr://{authority} resolves to {Name}Handler', () async {
  final match = await frRouter.resolve('fr://{authority}');
  expect(match, isNotNull);
  expect(frRouter.findHandler(match!.authority), isA<{Name}Handler>());
});
```

### bootstrap 注册模板

```dart
// lib/core/schema/bootstrap_routes.dart 的 registerAllFrRoutes() 内
FrRoute('{authority}', handler: const {Name}Handler()),
```

### MethodChannel 翻译模板（main.dart）

```dart
// _handleMethodCall 的 switch 内
'navigateTo{Name}' => 'fr://{authority}',
```

---

## 命名约定

| 元素 | 约定 | 示例 |
|------|------|------|
| handler 类 | `{Name}Handler`，PascalCase | `SettingsHandler` |
| handler 文件 | `{name}_handler.dart`，snake_case | `settings_handler.dart` |
| fr:// authority | 全小写，多段用 `/` | `settings`、`lab/demo`、`notion/image-host` |
| MethodChannel method | `navigateTo{Name}`，PascalCase | `navigateToSettings` |
| 目标 Page | 独立文件，handler 引用它 | `SettingsPage` |
| **demo URL slug** | **纯 ASCII 小写 + 连字符**，子类 `@override String get slug` 自带 | `clock`、`calendar`、`notion-image-host` |
| demo 显示 title | 中文，仅作 UI 显示，**不进 URL** | `时钟`、`日历待办`、`Notion 图床` |

---

## 何时该加路由 / 何时不需要

**该注册 fr:// 路由**：
- 用户能从文本链接跳转的页面
- 桌面 widget / 通知 / Shortcut 能唤起的页面
- 多个入口（按钮 + 文本 + native）都要跳的页面

**不需要注册**（直接 Navigator.push 即可）：
- 仅在某个流程内部、单一按钮触发的次级页面（如"从设置点进二级详情"）
- 不会被 fr:// 字符串引用的临时页面

> 判断标准：**这个页面会不会出现在 `fr://...` 字符串里？** 不会就不必注册。

---

## 相关文件

- 设计 ref：`reffenrece/Flutter-自定义Scheme路由中心化-fr-Router.md`（理解系统 + 设计陷阱）
- 核心实现：`lib/core/schema/fr_*.dart` + `lib/core/schema/handlers/*.dart`
- 集中注册：`lib/core/schema/bootstrap_routes.dart`
- MethodChannel 翻译：`lib/main.dart` 的 `_handleMethodCall`
- 测试范例：`test/core/schema/migration_test.dart`
