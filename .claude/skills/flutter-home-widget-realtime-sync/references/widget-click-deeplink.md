# 桌面小组件点击 → 直达具体 Demo 页面

本 ref 沉淀自 2026-07 `clock_widget` "点击直达 clock 页面"实战(用户反馈:点击 widget 只进 lab 首页,多一步跳转)。

适用任何 **widget 主体点击 → 打开 Flutter 内某个具体页面** 的场景,与现有 `fr://` 路由体系无缝对接。

## 何时读这个 ref

- 用户反馈"点击 widget 进入的是首页/列表,想直接进入具体页面"
- 第一次为 widget 加 `setOnClickPendingIntent(R.id.widget_root, ...)`
- 给新 widget(`CalendarWidget`/`TimetableWidget` 等)做主体点击跳转
- 想利用现有 `fr://lab/demo/{slug}` 路由而不重新写一套 Intent extra 解析
- 排查 "widget 点击后页面被多次 push / 返回手势要折叠多次" 类 bug

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
│ main.dart _handleMethodCall            │
│   └─ switch call.method:               │  ③ "navigateToClock" → "fr://lab/demo/clock"
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
- 与 calendar/timetable/notion 的做法完全对称,后续维护一致
- 调试时 `adb shell am start -a android.intent.action.VIEW -d "fr://lab/demo/clock"` 可直接拉起测试

## 关键代码模式(以 clock 为例)

### 1. ClockWidgetProvider.kt —— 主体点击 Intent

```kotlin
// ClockWidgetProvider.kt:84-96 (updateAppWidget 内)
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
// MainActivity.kt:217-233 (handleIntent when 分支)
when {
    uriStr == "fr://calendar" || uri.path == "/calendar" -> {
        widgetChannel.notifyNavigateToCalendar()
    }
    uriStr == "fr://clock" || uriStr == "fr://lab/demo/clock" ||
        uri.path == "/lab/demo/clock" -> {                       // ← 新增
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
                "navigateToCalendar" -> { onNavigateToCalendar?.invoke(); result.success(null) }
                "navigateToClock" -> { onNavigateToClock?.invoke(); result.success(null) }  // ← 新增
                "navigateToTimetable" -> { onNavigateToTimetable?.invoke(); result.success(null) }
                "navigateToNotionImage" -> {
                    val autocapture = call.argument<Boolean>("autocapture") ?: false
                    onNavigateToNotionImage?.invoke(autocapture)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    var onNavigateToLab: (() -> Unit)? = null
    var onNavigateToCalendar: (() -> Unit)? = null
    var onNavigateToClock: (() -> Unit)? = null           // ← 新增
    var onNavigateToTimetable: (() -> Unit)? = null
    var onNavigateToNotionImage: ((Boolean) -> Unit)? = null

    fun notifyNavigateToLab() { channel.invokeMethod("navigateToLab", null) }
    fun notifyNavigateToCalendar() { channel.invokeMethod("navigateToCalendar", null) }
    fun notifyNavigateToClock() { channel.invokeMethod("navigateToClock", null) }   // ← 新增
    fun notifyNavigateToTimetable() { channel.invokeMethod("navigateToTimetable", null) }
    fun notifyNavigateToNotionImage(autocapture: Boolean) {
        channel.invokeMethod("navigateToNotionImage", autocapture)
    }
}
```

**对称性原则**:每次给 `handleIntent` 加新深链,都对应 `navigateToXxx` method + `onNavigateToXxx` 回调 + `notifyNavigateToXxx()` 调用 —— 这三处必须同时改,缺一会出现"日志说 invoke 了但 Flutter 端 switch 没命中"。

### 4. main.dart —— _handleMethodCall 翻译成 fr:// URL

```dart
// lib/main.dart:108-121
Future<dynamic> _handleMethodCall(MethodCall call) async {
  final frUrl = switch (call.method) {
    'navigateToLab' => 'fr://lab',
    'navigateToCalendar' => 'fr://lab/demo/calendar',
    'navigateToClock' => 'fr://lab/demo/clock',         // ← 新增
    'navigateToTimetable' => 'fr://timetable',
    'navigateToNotionImage' =>
      'fr://notion/image-host?autocapture=${(call.arguments as bool?) ?? false}',
    _ => null,
  };
  if (frUrl == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    FrNavigator.handle(navigatorKey.currentContext, frUrl);
  });
}
```

**为什么用 `addPostFrameCallback`?**

MethodChannel 回调可能在 build 阶段触发,直接 `nav.push` 会抛 "Navigator is currently locked"。
`addPostFrameCallback` 把 push 推迟到当前帧结束后,Flutter 端能干净地 push 新页面。

**为什么 `FrNavigator.handle` 已经够了?**

`FrNavigator.handle()` 内部已经做了 4 件事,不需要在 main.dart 重复实现:
- `frRouter.resolve(url)` —— 解析 URL 找 handler
- 防重复堆叠 —— 探查栈顶 route name,如果已 push 过同名 route 直接 return
- `MaterialPageRoute(settings: RouteSettings(name: ...))` —— 给每条 fr:// 路由唯一命名
- `nav.push(target)` —— 真正入栈

## 必踩坑:防重复堆叠

`FrNavigator.handle()` (`lib/core/schema/fr_navigator.dart:51-69`) 用 `RouteSettings.name` 探查栈顶:

```dart
final routeName = '/fr/${match.authority}/${match.path}';
String? currentName;
nav.popUntil((route) {
  currentName = route.settings.name;
  return true; // 立即停止,不会 pop 任何页面
});
if (currentName == routeName) return;
nav.push(MaterialPageRoute(settings: RouteSettings(name: routeName), builder: ...));
```

**为什么要做这个?**

桌面 widget 点击、冷启动 Intent、`onNewIntent` 三个入口都会触发同一条 fr:// URL。
不做这个检查会出现:
- 用户点 widget 一次 → push clock
- 滑出 app → 再次点 widget → 又 push 一个 clock
- 退出要按两次 back

## 错误案例

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| widget 点击 Intent data 写 `"fr://lab"` | 进入 lab 首页,用户要多点一次才能到目标 demo | 写完整深链 `"fr://lab/demo/{slug}"`,命中 `LabDemoHandler` |
| 改 `WidgetChannel.kt` 加 `navigateToClock` 但忘改 `MainActivity.handleIntent` when 分支 | handleIntent 永远命中不到 `fr://lab/demo/clock`,变成"logcat 看到 invoke 但 Flutter 端不进栈" | 三处同改:handleIntent when + WidgetChannel + main.dart switch |
| `main.dart` switch 里把 `navigateToClock` 写成 `fr://lab`(而不是 `fr://lab/demo/clock`) | 翻译成 fr://lab 后走 `LabIndexHandler`,进首页 | 必须翻译成最终路由 URL,与 `bootstrap_routes.dart` 注册的 authority 严格对齐 |
| 直接 `Navigator.pushNamed` 绕过 FrNavigator | 失去防重复堆叠 / 失去 SnackBar 错误提示 / 失去和 fr:// 路由体系的一致性 | 统一走 `FrNavigator.handle(context, frUrl)`,享受所有已有防护 |
| 改完不删桌面旧 widget 实例 | 部分 launcher 把 Intent Intent extras 缓存,看不到新效果 | 长按删除旧 widget,重新从 picker 添加(只针对改 manifest 的场景;改 Intent.data 通常无需重添) |
| PendingIntent requestCode 写 `appWidgetId` 配合 `getActivity` | 无害但不必要;`getActivity` 走系统启动器,系统按 data 区分 | `getActivity` 用 0 即可,只有 `getBroadcast`/`getService` 需要 appWidgetId |
| 漏写 `FLAG_IMMUTABLE` (Android 12+) | `IllegalArgumentException` 崩溃,widget 完全无法点击 | `FLAG_UPDATE_CURRENT or FLAG_IMMUTABLE` |

## 验证清单

修改 widget 点击跳转后,按序检查:

- [ ] `flutter analyze` 0 error
- [ ] `flutter build apk --debug` 成功(Kotlin 编译过)
- [ ] `WidgetChannel.kt` 三处齐全: when 分支 / `onNavigateToXxx` 字段 / `notifyNavigateToXxx()` 方法
- [ ] `MainActivity.handleIntent` when 分支包含新 URI,且与 WidgetChannel method name 一致
- [ ] `main.dart _handleMethodCall` switch 包含新 method,翻译出的 fr:// URL 与 `bootstrap_routes.dart` 注册的 authority 对齐
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

### Step 3: MainActivity.kt + main.dart 各加一行

```kotlin
// MainActivity.kt handleIntent when
uriStr == "fr://lab/demo/<slug>" -> widgetChannel.notifyNavigateToXxx()

// main.dart _handleMethodCall switch
'navigateToXxx' => 'fr://lab/demo/<slug>',
```

**主 SKILL.md 不用动** —— 整个 widget 端点击跳转是这次实战提炼出的独立主题,在这里沉淀。新 widget 按这 3 步复制即可。