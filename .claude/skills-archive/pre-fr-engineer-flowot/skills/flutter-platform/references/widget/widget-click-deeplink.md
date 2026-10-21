# 桌面小组件点击 → 直达具体 Demo 页面

本 ref 沉淀自 2026-07 `clock_widget` "点击直达 clock 页面"实战(用户反馈:点击 widget 只进 lab 首页,多一步跳转)。
2026-08 补充:录音机 widget / notion widget 深链失效实战 → 新增「带 query 的 URI 必须 `startsWith`」必踩坑。

适用任何 **widget 主体点击 → 打开 Flutter 内某个具体页面** 的场景,与现有 `fr://` 路由体系无缝对接。

## 何时读这个 ref

- 用户反馈"点击 widget 进入的是首页/列表,想直接进入具体页面"
- 第一次为 widget 加 `setOnClickPendingIntent(R.id.widget_root, ...)`
- 给新 widget(`RecorderWidget`/`TimetableWidget` 等)做主体点击跳转
- 想利用现有 `fr://lab/demo/{slug}` 路由而不重新写一套 Intent extra 解析
- 排查 "widget 点击后页面被多次 push / 返回手势要折叠多次" 类 bug
- 排查 "点击 widget 只进 app 首页,进不到 demo,且 notion/recorder 都失效" 类 bug → **带 query 的 URI 用 `==` 匹配了**(见下方必踩坑)

## 核心架构:Intent.data → fr:// URL → Flutter 路由

整条链 4 段、跨 3 个 runtime,每段都有现成机制,不需要发明新东西:

```
┌──────────── Android 原生层 ────────────┐
│ ClockWidgetProvider.kt (Kotlin)        │
│   └─ setOnClickPendingIntent(          │  ① Intent.data = "fr://lab/demo/clock"
│        R.id.widget_root,              │
│        PendingIntent.getActivity(...)) │
└──────────────────┬─────────────────────┘
                   │ 启动 / onNewIntent
                   ▼
┌──────────── Android 原生层 ────────────┐
│ MainActivity.kt (Kotlin)               │
│   └─ handleIntent(intent)              │  ② uriStr.startsWith("fr://lab/demo/clock")
│        → widgetChannel.notifyNavigate… │     → MethodChannel
└──────────────────┬─────────────────────┘
                   │ "navigateToClock"
                   ▼
┌──────────── Flutter 端 ────────────────┐
│ main.dart _handleRootMethodCall        │
│   └─ FrMethodChannelTranslator         │  ③ "navigateToClock" → "fr://lab/demo/clock"
│      .translate(call)                  │
│        → FrNavigator.handle(           │
│           navigatorKey.currentContext, │
│           frUrl)                       │
└──────────────────┬─────────────────────┘
                   │ resolve + findHandler + push
                   ▼
┌──────────── Flutter 端 ────────────────┐
│ FrNavigator.handle()                   │
│   ├─ frRouter.resolve(url)             │  ④ 命中 lab/demo authority
│   ├─ handler.build() → _DemoDetailPage │     → LabDemoHandler
│   └─ nav.push(MaterialPageRoute)       │
│       (带 RouteSettings.name 防重复)   │
└────────────────────────────────────────┘
```

**为什么走 `Intent.data` 而不是 Intent extra?**

- `fr://lab/demo/clock` 是字符串,放 Intent.data 是 Android 标准的"深链"模式
- `MainActivity` 已有的 `handleIntent` 就是按 `intent.data` 分发的,白嫖现有代码
- 与 timetable/notion/recorder 的做法完全对称,后续维护一致
- 调试时 `adb shell am start -a android.intent.action.VIEW -d "fr://lab/demo/clock"` 可直接拉起测试

## 关键代码模式(以 clock 为例)

### 1. ClockWidgetProvider.kt —— 主体点击 Intent

```kotlin
// ClockWidgetProvider.kt — updateAppWidget 内主体点击段
val intent = Intent(context, MainActivity::class.java).apply {
    action = Intent.ACTION_VIEW
    data = android.net.Uri.parse("fr://lab/demo/clock")  // ← 直达 demo 页面
    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
}
val pendingIntent = PendingIntent.getActivity(
    context,
    0,
    intent,
    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
)
setOnClickPendingIntent(R.id.widget_container, pendingIntent)
```

⚠️ **requestCode 用 `0` 还是 `appWidgetId`?**

- 打开 Activity(Intent.getActivity)**不**需要 `appWidgetId` 作 requestCode
- 只有 `PendingIntent.getBroadcast` / `getService` 这类"在同一进程内分发"的场景,才需要 `appWidgetId` 区分多实例
- 这里 PendingIntent 走的是 Activity 启动器,系统按 Intent data + component 区分,requestCode 写 0 无害

### 2. MainActivity.kt —— handleIntent 加 fr:// URL 解析

```kotlin
// MainActivity.kt — handleIntent when 分支
when {
    // fr://recorder 短别名 + fr://lab/demo/recorder 主链 + path 兜底（与时钟走同一模式）
    uriStr == "fr://recorder" || uriStr.startsWith("fr://lab/demo/recorder") ||
        uri.path == "/demo/recorder" -> {
        // 桌面 widget 默认 autostart=true；普通 fr:// 链接可显式 ?autostart=false
        widgetChannel.notifyNavigateToRecorder(uri.getBooleanQueryParameter("autostart", true))
    }
    uriStr == "fr://clock" || uriStr.startsWith("fr://lab/demo/clock") ||
        uri.path == "/lab/demo/clock" -> {
        widgetChannel.notifyNavigateToClock()
    }
    uriStr == "fr://timetable" || uri.path == "/timetable" -> {
        widgetChannel.notifyNavigateToTimetable()
    }
    uriStr == "fr://lab" || uri.path == "/lab" -> {
        widgetChannel.notifyNavigateToLab()
    }
}
```

> ⚠️ **⚠️ 带 query 的 URI 必须用 `startsWith`,不能用 `==`。** 见下方「必踩坑:query URI 精确匹配失效」。

**为何三种 URI 都接受?**

| 写法 | 用途 |
|------|------|
| `fr://lab/demo/clock` | 生产深链,与 fr:// 路由表严格对齐 |
| `fr://clock` | 短别名,给外部测试 / 老链接兼容 |
| `/lab/demo/clock` | App Links / 第三方拉起时的 path 形式 |

不写也行,但加上能少一类用户反馈"我点了 widget 没反应"。

### 3. WidgetChannel.kt —— 新增 navigateToClock 回调

```kotlin
// WidgetChannel.kt
class WidgetChannel(messenger: BinaryMessenger) {
    companion object {
        const val NAME = "io.github.xiaodouzi.fr/widget"
    }

    private val channel = MethodChannel(messenger, NAME).apply {
        setMethodCallHandler { call, result ->
            when (call.method) {
                "navigateToLab" -> { onNavigateToLab?.invoke(); result.success(null) }
                "navigateToClock" -> { onNavigateToClock?.invoke(); result.success(null) }
                "navigateToTimetable" -> { onNavigateToTimetable?.invoke(); result.success(null) }
                "navigateToNotionImage" -> {
                    val autocapture = call.argument<Boolean>("autocapture") ?: false
                    onNavigateToNotionImage?.invoke(autocapture)
                    result.success(null)
                }
                "navigateToRecorder" -> {
                    val autostart = call.argument<Boolean>("autostart") ?: true
                    onNavigateToRecorder?.invoke(autostart)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    var onNavigateToLab: (() -> Unit)? = null
    var onNavigateToClock: (() -> Unit)? = null
    var onNavigateToTimetable: (() -> Unit)? = null

    /// Notion 图床页面跳转回调，[autocapture] = true 表示从桌面 widget 进入，
    /// 期望自动触发拍照。
    var onNavigateToNotionImage: ((Boolean) -> Unit)? = null

    /// 录音机页面跳转回调，[autostart] = true 表示从桌面 widget 进入，
    /// 期望自动开始录音。
    var onNavigateToRecorder: ((Boolean) -> Unit)? = null

    fun notifyNavigateToLab() { channel.invokeMethod("navigateToLab", null) }
    fun notifyNavigateToClock() { channel.invokeMethod("navigateToClock", null) }
    fun notifyNavigateToTimetable() { channel.invokeMethod("navigateToTimetable", null) }
    fun notifyNavigateToNotionImage(autocapture: Boolean) {
        channel.invokeMethod("navigateToNotionImage", autocapture)
    }
    fun notifyNavigateToRecorder(autostart: Boolean) {
        channel.invokeMethod("navigateToRecorder", autostart)
    }
}
```

**对称性原则**:每次给 `handleIntent` 加新深链,都对应 `navigateToXxx` method + `onNavigateToXxx` 回调 + `notifyNavigateToXxx()` 调用 —— 这三处必须同时改,缺一会出现"日志说 invoke 了但 Flutter 端 switch 没命中"。

### 4. FrMethodChannelTranslator —— MethodChannel call 翻译成 fr:// URL（main.dart 一行委托）

`call.method → fr:// URL` 翻译表已抽到独立类 `FrMethodChannelTranslator`（`lib/app_lifecycle/fr_method_channel_translator.dart`，与 `WidgetChannel.kt` 的 `when` 分支严格对称）。`main.dart` 只剩一行委托：

```dart
// lib/main.dart
Future<dynamic> _handleRootMethodCall(MethodCall call) async {
  final frUrl = FrMethodChannelTranslator.translate(call);
  if (frUrl == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    FrNavigator.handle(rootNavigatorKey.currentContext, frUrl);
  });
}
```

**加新 widget → 只需往 `FrMethodChannelTranslator.translate` 的 switch 加一行 case**（同步在 `WidgetChannel.kt` 加对应 `when` 分支 + 回调 + notify 方法，「三件套」）。`main.dart` 与 `bootstrap_routes.dart` 都不动。

**为什么用 `addPostFrameCallback`?**

MethodChannel 回调可能在 build 阶段触发，直接 `nav.push` 会抛 "Navigator is currently locked"。
`addPostFrameCallback` 把 push 推迟到当前帧结束后，Flutter 端能干净地 push 新页面。

**为什么 `FrNavigator.handle` 已经够了?**

`FrNavigator.handle()` 内部已经做了 4 件事，不需要在 main.dart 重复实现：
- `frRouter.resolve(url)` —— 解析 URL 找 handler
- 防重复堆叠（CLEAR_TOP 语义）—— 见下方「必踩坑:防重复堆叠」
- `MaterialPageRoute(settings: RouteSettings(name: ...))` —— 给每条 fr:// 路由唯一命名
- `nav.push(target)` —— 真正入栈

## 必踩坑:防重复堆叠（CLEAR_TOP 语义）

`FrNavigator.handle()`（`lib/core/schema/fr_navigator.dart` 的 `handle` 方法）走的是 **CLEAR_TOP 语义**：目标路由已在栈中（任意深度）→ `popUntil` 把已存在实例提到栈顶，不再 push；不在栈中 → 正常 push。栈是否已有目标路由的判定委托给 `FrRouteStack`（NavigatorObserver，`main.dart` 注册到 `MaterialApp.navigatorObservers`）跟踪全栈。

```dart
// lib/core/schema/fr_navigator.dart（handle 方法末尾）
final routeName = '/fr/${match.authority}/${match.path}';
if (frRouteStack.containsName(routeName)) {
  nav.popUntil(
    (route) => route.settings.name == routeName || route.isFirst,
  );
  return;
}
nav.push(
  MaterialPageRoute(
    settings: RouteSettings(name: routeName),
    builder: (_) => target,
  ),
);
```

`route.isFirst` 是保险：Observer 与栈漂移时最多 pop 到根页，不会清空调。

**为什么不能只探查栈顶 route name 就 return？** 旧实现就是只查栈顶——桌面 widget 交替点不同入口、或目标页之上压了其他页面时，同一页面会被反复 push，"返回手势因此要折叠多次才能退出"。改成「任意深度 containsName + popUntil 上提」后，行为对齐 Android `Intent.FLAG_ACTIVITY_CLEAR_TOP`。

**场景**:

桌面 widget 点击、冷启动 Intent、`onNewIntent` 三个入口都会触发同一条 fr:// URL。
不做 CLEAR_TOP 会出现:
- 用户点 widget 一次 → push clock
- 滑出 app → 再次点 widget → 又 push 一个 clock
- 退出要按两次 back

## 必踩坑:带 query 的 URI 必须 `startsWith`,不能 `==`

> 沉淀自 2026-08 录音机 widget + notion widget 深链失效实战。
> 症状:点击 widget 只进 app 首页,进不到对应 demo,logcat 里
> `MainActivity` 无任何 `navigateToXxx` 日志(handleIntent 静默 drop)。

**根因**:`Uri.parse("fr://lab/demo/recorder?autostart=true")` 拆解后:

```kotlin
uriStr        = "fr://lab/demo/recorder?autostart=true"  // 带 query,不再等于纯 path
uri.authority = "lab"                                     // host 段
uri.path      = "/demo/recorder"                          // 不含 "lab"(authority 里)
```

所以 **widget 发出的带 query 的 URI,任何一个 `==` 条件都匹配不上**:

```kotlin
// ❌ 错误:widget 发 fr://lab/demo/recorder?autostart=true,三个 == 全 miss → 静默 drop
uriStr == "fr://recorder" || uriStr == "fr://lab/demo/recorder" ||
    uri.path == "/lab/demo/recorder" -> { ... }

// ✅ 正确:startsWith 天然兼容带 query 与不带 query
uriStr == "fr://recorder" || uriStr.startsWith("fr://lab/demo/recorder") ||
    uri.path == "/demo/recorder" -> { ... }   // ← path 也要对齐 Uri 语义(不含 authority)
```

**判定规则**:

| 场景 | 用 `==` | 用 `startsWith` |
|------|---------|-----------------|
| URI 永远无 query(如 clock widget `fr://lab/demo/clock`) | ✅ 可 | ✅ 也可 |
| URI 可能带 query(如 notion `fr://notionimg?autocapture=1`、recorder `?autostart=true`) | ❌ 必 miss | ✅ 必须 |

**通用原则**:handleIntent 的 when 分支一律用 `startsWith(prefix)` 兜底 query,
尤其当 widget PendingIntent 里带了 `?xxx=true` 这类动作参数时。

**`uri.path` 分支的第二个坑**:`Uri.path` 返回的是 **authority 之后的 path 段**,
不含 host(`fr://lab/demo/recorder` 的 path 是 `/demo/recorder`,不是 `/lab/demo/recorder`)。
写 `uri.path == "/lab/demo/recorder"` 永远匹配不到 —— 要么写 `/demo/recorder`,
要么干脆省略 path 分支,只靠 `startsWith` 就够了。

## 错误案例

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| widget 点击 Intent data 写 `"fr://lab"` | 进入 lab 首页,用户要多点一次才能到目标 demo | 写完整深链 `"fr://lab/demo/{slug}"`,命中 `LabDemoHandler` |
| 改 `WidgetChannel.kt` 加 `navigateToClock` 但忘改 `MainActivity.handleIntent` when 分支 | handleIntent 永远命中不到 `fr://lab/demo/clock`,变成"logcat 看到 invoke 但 Flutter 端不进栈" | 三处同改:handleIntent when + WidgetChannel + FrMethodChannelTranslator.translate |
| `FrMethodChannelTranslator` translate 里把 `navigateToClock` 写成 `fr://lab`(而不是 `fr://lab/demo/clock`) | 翻译成 fr://lab 后走 `LabIndexHandler`,进首页 | 必须翻译成最终路由 URL,与 `bootstrap_routes.dart` 注册的 authority 严格对齐 |
| 直接 `Navigator.pushNamed` 绕过 FrNavigator | 失去防重复堆叠 / 失去 SnackBar 错误提示 / 失去和 fr:// 路由体系的一致性 | 统一走 `FrNavigator.handle(context, frUrl)`,享受所有已有防护 |
| 改完不删桌面旧 widget 实例 | 部分 launcher 把 Intent Intent extras 缓存,看不到新效果 | 长按删除旧 widget,重新从 picker 添加(只针对改 manifest 的场景;改 Intent.data 通常无需重添) |
| PendingIntent requestCode 写 `appWidgetId` 配合 `getActivity` | 无害但不必要;`getActivity` 走系统启动器,系统按 data 区分 | `getActivity` 用 0 即可,只有 `getBroadcast`/`getService` 需要 appWidgetId |
| 漏写 `FLAG_IMMUTABLE` (Android 12+) | `IllegalArgumentException` 崩溃,widget 完全无法点击 | `FLAG_UPDATE_CURRENT or FLAG_IMMUTABLE` |
| widget 发 `fr://lab/demo/recorder?autostart=true`,handleIntent 用 `==` 精确匹配 | 三个 `==` 条件全 miss,handleIntent 静默 drop → 点击 widget 只进 app 首页,进不到 demo | 用 `startsWith("fr://lab/demo/recorder")` 兜底 query |
| `uri.path == "/lab/demo/recorder"` | `Uri.path` 是 authority 之后的段 = `/demo/recorder`,此条件永远匹配不到 | 写 `/demo/recorder`,或省略 path 分支只靠 `startsWith` |

## 验证清单

修改 widget 点击跳转后,按序检查:

- [ ] `flutter analyze` 0 error
- [ ] `flutter build apk --debug` 成功(Kotlin 编译过)
- [ ] `WidgetChannel.kt` 三处齐全: when 分支 / `onNavigateToXxx` 字段 / `notifyNavigateToXxx()` 方法
- [ ] `MainActivity.handleIntent` when 分支包含新 URI,且与 WidgetChannel method name 一致
- [ ] **带 query 的 URI 用 `startsWith` 匹配**(`fr://xxx?flag=true` 用 `==` 会静默 drop;`uri.path` 不含 authority 段)
- [ ] `FrMethodChannelTranslator.translate` switch 包含新 case,翻译出的 fr:// URL 与 `bootstrap_routes.dart` 注册的 authority 对齐
- [ ] **冷启动验证**:kill app → 点 widget → 应直接进入目标 demo(不经过 lab 首页)
- [ ] **温启动验证**:app 在后台 → 点 widget → 应直接进入目标 demo,不堆叠新实例
- [ ] **返回手势验证**:进入目标 demo 后按一次 back,应回到 MainScreen(不是再 pop 一层同名 demo)
- [ ] **adb 拉起测试**(可选): `adb shell am start -a android.intent.action.VIEW -d "fr://lab/demo/clock"` 应能拉起

## 给新 widget 加跳转的 SOP(3 步)

> 适用任何 "新建 Widget X → 点击直达 demo X" 的场景。

### Step 1: 在 WidgetXxxProvider.kt 主体点击 Intent data 写完整 fr:// URL

```kotlin
data = android.net.Uri.parse("fr://lab/demo/<demo-slug>")
```

demo-slug 必须等于 `DemoPage.slug`(见 `lib/lab/lab_container.dart:DemoPage.slug`)。

### Step 2: 在 WidgetChannel.kt 加 `navigateToXxx` 三件套

```kotlin
// ① when 分支
"navigateToXxx" -> { onNavigateToXxx?.invoke(); result.success(null) }
// ② 回调字段
var onNavigateToXxx: (() -> Unit)? = null
// ③ 主动通知方法
fun notifyNavigateToXxx() { channel.invokeMethod("navigateToXxx", null) }
```

### Step 3: MainActivity.kt + FrMethodChannelTranslator 各加一行

```kotlin
// MainActivity.kt handleIntent when
// ⚠️ 用 startsWith 而不是 == —— 若 widget 带 ?autostart=true 之类 query,== 必 miss(见上方必踩坑)
uriStr == "fr://lab/demo/<slug>" || uriStr.startsWith("fr://lab/demo/<slug>") ->
    widgetChannel.notifyNavigateToXxx()

// lib/app_lifecycle/fr_method_channel_translator.dart translate switch
'navigateToXxx' => 'fr://lab/demo/<slug>',
```

**main.dart 不动**:翻译已收口到 `FrMethodChannelTranslator`,新 widget 只需往该类 `translate` 加一行 case。

**主 SKILL.md 不用动** —— 整个 widget 端点击跳转是这次实战提炼出的独立主题,在这里沉淀。新 widget 按这 3 步复制即可。