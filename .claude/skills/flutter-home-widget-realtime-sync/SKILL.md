---
name: flutter-home-widget-realtime-sync
description: Flutter 通过 home_widget 把 1Hz 实时值（如倒计时）推到 Android 桌面 AppWidget 的端到端架构。当用户提到 home_widget 不同步、桌面小组件不刷新、appwidget 实时值、widget 显示卡死、widget 进程被杀场景、AppWidgetProvider 找不到时触发。
---

# Flutter ↔ Android Home Widget 实时值同步

## 触发场景

用户描述任意以下情况时，本 skill 必须被调用：

- "桌面小组件不同步" / "widget 不刷新" / "首页 widget 时间停了"
- "home_widget 调用没反应" / "updateWidget 不触发 onUpdate"
- "AppWidgetProvider 收不到广播"
- "Flutter 进程被杀后 widget 数据冻结"
- "widget 30 分钟才更新一次" / "只有系统周期才刷"
- "ClassNotFoundException ClockWidgetProvider" 类似报错
- 任何 "把 1Hz 实时值推到 Android 桌面" 的需求

## 核心原则（按重要性排序）

### 原则 1：永远用 `qualifiedAndroidName` —— 这是 90% bug 的根因

home_widget 插件源码 (`HomeWidgetPlugin.kt:105`):
```kotlin
val javaClass = Class.forName(qualifiedName ?: "${context.packageName}.${className}")
```

只要你的 `AppWidgetProvider` 不在根包名直接下、而是在 `.native.widget` 等子包下，传 `androidName` 必然 `ClassNotFoundException`。**异常被插件 catch 后静默吞掉**，导致：
- `onUpdate` 永远不被 Flutter 触发
- widget 只能等系统默认周期（最快 30 分钟）被动刷新
- 调试时看不到任何报错，极难排查

```dart
// ❌ 错误（包名 + ClockWidgetProvider 找不到子包下的类）
HomeWidget.updateWidget(
  name: 'ClockWidgetProvider',
  androidName: 'ClockWidgetProvider',
);

// ✅ 正确
static const String _qualifiedAndroidName =
    'io.github.xiaodouzi.fr.native.widget.ClockWidgetProvider';
HomeWidget.updateWidget(qualifiedAndroidName: _qualifiedAndroidName);
```

### 原则 2：永远做 "三层兜底" —— 进程在 / 进程死 / 用户手动

| 层  | 触发        | 数据源                          | 适用      |
| --- | ----------- | ------------------------------- | --------- |
| L1  | Flutter tick (1Hz) | Provider 内存 `remainingSeconds` | 应用前台/后台未杀 |
| L2  | 系统 onUpdate / 用户点刷新 | 原生侧基于 `startTimeMs` 重算    | Flutter 已死 |
| L3  | 用户主动点刷新按钮 | 同 L2，但**立即生效**           | 永远可用 |

实现要点：
- **L1**：`_syncToWidget()` 写满 SharedPreferences，调用 `updateWidget`
- **L2**：Provider 写入 `clock_start_time_ms` + `clock_start_remaining_seconds`，**Kotlin 侧 onUpdate 用 `System.currentTimeMillis() - startTimeMs` 自行算 remaining**
- **L3**：XML 加 `🔄` TextView，`PendingIntent.getBroadcast(context, appWidgetId, ACTION_REFRESH_intent, FLAG_IMMUTABLE)` 触发自己的 `onReceive`

### 原则 3：1Hz 高频写必须去重 + 并发

```dart
static bool _isUpdating = false;

static Future<void> updateClockWidget(ClockWidgetData data) async {
  if (_isUpdating) return;          // tick 去重：还在写就跳过新请求
  _isUpdating = true;
  try {
    await Future.wait([              // 并发：9 个 key 同时写 ≈ 9× 提速
      HomeWidget.saveWidgetData(_keyTitle, data.title),
      HomeWidget.saveWidgetData(_keyRemainingSeconds, data.remainingSeconds.toString()),
      // ... 其余 7 个 key
    ]);
    await HomeWidget.updateWidget(qualifiedAndroidName: _qualifiedAndroidName);
  } catch (e, stack) {
    debugPrint('[Service] failed: $e\n$stack');
  } finally {
    _isUpdating = false;
  }
}
```

不要顺序 `await` 9 次 saveWidgetData，会让 tick 慢到 200ms+，1Hz 节奏失稳。

### 原则 4：`lazy: false` 让 Provider 冷启动即同步

```dart
classic_provider.ChangeNotifierProvider(
  lazy: false,                       // ← 关键，否则进入页面才同步，冷启动 widget 是空的
  create: (_) => LabClockProvider(), // 构造函数里 loadClocks() → _syncToWidget()
),
```

### 原则 5：多 widget 实例用 `appWidgetId` 做 PendingIntent requestCode

```kotlin
val refreshPi = PendingIntent.getBroadcast(
  context,
  appWidgetId,                       // ← 不要写 0，否则多实例共享 Intent
  refreshIntent,
  PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE  // 12+ 必须 IMMUTABLE
)
```

## 端到端架构（最小可用配方）

```
┌─────────── Flutter ───────────┐         ┌─────────── Android ───────────┐
│  LabClockProvider             │         │  ClockWidgetProvider (Kotlin) │
│   ├─ Timer.periodic(1s)       │ tick    │   ├─ onUpdate(ids)            │
│   ├─ _syncToWidget()          │────────>│   │   └─ updateAppWidget × N  │
│   ├─ ClockWidgetService       │         │   ├─ onReceive(ACTION_REFRESH)│
│   │   └─ updateWidget(        │         │   │   └─ updateAppWidget × N  │
│   │       qualifiedAndroidName│         │   └─ updateAppWidget(ctx, id) │
│   │     )                     │         │       ├─ getData(prefs)       │
│   └─ WidgetsBindingObserver   │         │       ├─ remaining =          │
│       └─ on resume:           │  load   │       │   (isRunning && st>0) │
│           recalc + sync       │<────────│       │     ? startRemain -   │
└──────────────┬────────────────┘         │       │       (now - st)/1s  │
               │ saveWidgetData × N       │       │     : savedRemaining  │
               ▼                          │       └─ RemoteViews(...)     │
       ┌───────────────────┐              └──────────────┬────────────────┘
       │ SharedPreferences │<────────────────────────────┘ getData
       │ (HomeWidgetPlugin)│
       └───────────────────┘
```

## 关键代码模式

### A. Dart 端 Service（src: `lib/native/home_widget/clock_widget_service.dart`）

```dart
class ClockWidgetService {
  static const String _qualifiedAndroidName =
      'io.github.xiaodouzi.fr.native.widget.ClockWidgetProvider';
  static bool _isUpdating = false;

  static Future<void> updateClockWidget(ClockWidgetData data) async {
    if (_isUpdating) return;
    _isUpdating = true;
    try {
      await Future.wait([
        HomeWidget.saveWidgetData('clock_title', data.title),
        HomeWidget.saveWidgetData('clock_remaining_seconds', data.remainingSeconds.toString()),
        HomeWidget.saveWidgetData('clock_is_running', data.isRunning ? '1' : '0'),
        HomeWidget.saveWidgetData('clock_start_time_ms', data.startTimeMs.toString()),
        HomeWidget.saveWidgetData('clock_start_remaining_seconds', data.startRemainingSeconds.toString()),
        // ... 其余 key
      ]);
      await HomeWidget.updateWidget(qualifiedAndroidName: _qualifiedAndroidName);
    } catch (e, stack) {
      debugPrint('[ClockWidgetService] failed: $e\n$stack');
    } finally {
      _isUpdating = false;
    }
  }
}
```

### B. Provider 冷启动同步（src: `lib/main.dart` + `lab_clock_provider.dart`）

```dart
// main.dart
classic_provider.ChangeNotifierProvider(
  lazy: false,
  create: (_) => LabClockProvider(),
),

// LabClockProvider
LabClockProvider() {
  _startTimer();                              // 1Hz tick
  WidgetsBinding.instance.addObserver(this);  // 监听 resume
  loadClocks();                               // 冷启动即加载 + 首次 sync
}

@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.resumed) {
    _recalculateRunningClocks();              // 用 startTime 重算
    _syncToWidget();                          // 强制同步一次
  }
}
```

### C. Kotlin 端原生重算（src: `ClockWidgetProvider.kt`）

```kotlin
internal fun updateAppWidget(context: Context, mgr: AppWidgetManager, id: Int) {
    val data = HomeWidgetPlugin.getData(context)
    val isRunning = data.getString("clock_is_running", "0") == "1"
    val saved = data.getString("clock_remaining_seconds", "0")?.toIntOrNull() ?: 0
    val startMs = data.getString("clock_start_time_ms", "0")?.toLongOrNull() ?: 0L
    val startRemain = data.getString("clock_start_remaining_seconds", "0")?.toIntOrNull() ?: saved

    // 进程在 → 用 saved；进程死 → 用 startTime 重算
    val remaining = if (isRunning && startMs > 0) {
        val elapsed = (System.currentTimeMillis() - startMs) / 1000
        (startRemain - elapsed).toInt()
    } else saved

    // ... RemoteViews.setTextViewText(...)
}
```

### D. 刷新按钮兜底（XML + Kotlin onReceive）

```xml
<!-- clock_widget.xml -->
<TextView
    android:id="@+id/widget_refresh"
    android:text="🔄"
    android:layout_gravity="bottom|start" />
```

```kotlin
const val ACTION_REFRESH = "io.github.xiaodouzi.fr.action.CLOCK_WIDGET_REFRESH"

override fun onReceive(context: Context, intent: Intent) {
    super.onReceive(context, intent)
    if (intent.action == ACTION_REFRESH) {
        val mgr = AppWidgetManager.getInstance(context)
        val ids = mgr.getAppWidgetIds(ComponentName(context, ClockWidgetProvider::class.java))
        for (id in ids) updateAppWidget(context, mgr, id)
    }
}

// 在 updateAppWidget 内绑定 PendingIntent
val refreshIntent = Intent(context, ClockWidgetProvider::class.java).apply { action = ACTION_REFRESH }
val refreshPi = PendingIntent.getBroadcast(
    context, appWidgetId, refreshIntent,
    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
)
views.setOnClickPendingIntent(R.id.widget_refresh, refreshPi)
```

### E. AndroidManifest.xml 注册

```xml
<receiver android:name=".native.widget.ClockWidgetProvider" android:exported="true">
    <intent-filter>
        <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
        <action android:name="io.github.xiaodouzi.fr.action.CLOCK_WIDGET_REFRESH" />
    </intent-filter>
    <meta-data
        android:name="android.appwidget.provider"
        android:resource="@xml/clock_widget_info" />
</receiver>
```

## 错误案例

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| 用 `androidName:'ClockWidgetProvider'` 触发 updateWidget | 子包下的 Provider 触发不到 `Class.forName`，异常被插件吞掉，widget 只能等系统 30 分钟周期刷新；调试时看不到任何报错 | 始终用 `qualifiedAndroidName` + 全限定类名 |
| 9 个 `saveWidgetData` 顺序 `await` | 1Hz tick 在慢设备上写 200ms+，节奏失稳；UI 看到时间跳秒 | `Future.wait([...])` 并发写，提速 ~9× |
| Provider 无 `lazy:false` | 冷启动后 widget 显示空数据，必须等用户进入相关页面才同步 | `ChangeNotifierProvider(lazy: false, ...)` |
| 只在 Flutter 端算 remaining | 进程被系统杀（低内存/久后台）后 widget 数据冻结 | 原生侧基于 `startTimeMs + startRemainingSeconds` 重算 |
| PendingIntent requestCode 全用 `0` | 多 widget 实例时点其中一个，所有 widget 行为混淆 | 用 `appWidgetId` 作 requestCode |
| Android 12+ 漏 `FLAG_IMMUTABLE` | `IllegalArgumentException` 崩溃，widget 完全无法点击 | `FLAG_UPDATE_CURRENT or FLAG_IMMUTABLE` |
| 没有 tick 去重 (`_isUpdating`) | 慢设备 IO 堆积，写一次要 5 秒，UI 卡死 | 在 Service 顶层加 `static bool _isUpdating` |
| Manifest 缺自定义 action intent-filter | 刷新按钮点击无响应，`onReceive` 收不到 | 加上 `<action android:name="...ACTION_REFRESH" />` |
| 修复时只改 Kotlin 重算逻辑，没排查 Flutter 触发链 | 看似修了"进程死亡时显示对"，但**正常运行时仍然 30 分钟一更**——根因没解决 | 先 grep `qualifiedAndroidName`、`Class.forName`，再看一次插件源码 |

## 验证清单

修改完代码后，按序检查：

- [ ] `flutter analyze` 0 error
- [ ] `flutter build apk --debug` 成功（Android 端 Kotlin 编译通过）
- [ ] 装机后 1Hz 内能看到 widget 时间在跳（验证 L1）
- [ ] 把应用从最近任务划掉，等 1 分钟再点 widget 刷新按钮，时间应跳到正确值（验证 L2 + L3）
- [ ] 添加两个 widget 实例，分别点各自刷新按钮互不干扰（验证 PendingIntent requestCode）
- [ ] Android 12+ 设备点刷新按钮不崩溃（验证 FLAG_IMMUTABLE）

## 排查 Flowchart

```
widget 不刷新
    │
    ├─ Flutter 端 print 显示 _syncToWidget 被调用？
    │   ├─ 否 → Provider 没启动 → 检查 lazy:false 和 main.dart 注册
    │   └─ 是 → 下一步
    │
    ├─ adb logcat | grep ClassNotFoundException？
    │   ├─ 是 → 用 qualifiedAndroidName 全限定类名
    │   └─ 否 → 下一步
    │
    ├─ Kotlin 端 updateAppWidget 被调用？(加 Log.d)
    │   ├─ 否 → 检查 AndroidManifest receiver 配置 + 全限定类名
    │   └─ 是 → 下一步
    │
    ├─ getData 拿到的值是新值？
    │   ├─ 否 → Future.wait 没等齐 / SharedPreferences 写慢 / _isUpdating 堵了
    │   └─ 是 → RemoteViews 没正确 setTextViewText / id 错
    │
    └─ Flutter 进程被杀后还正确？
        └─ 否 → 必须实现 startTimeMs 原生重算 (L2)
```

## 样式规范

本 skill 聚焦"实时值同步"的架构与代码模式,**widget 样式规范**(去 emoji、支持 1×1、launcher 兼容、layout 自适应)沉淀在独立 ref 中,设计或修改任何 widget layout/xml 之前必读:

→ [[widget-style-spec]]

**触发加载本 ref 的关键词**:
- "widget 样式优化" / "去掉 emoji"
- "支持 1×1" / "widget 太大"
- "某些 launcher 看不到 widget" / "launcher 兼容性"
- 第一次写 `widget_info.xml` 或修改 minWidth/minHeight/targetCell
- 用户反馈 widget 在桌面显示异常

## 调用 skill-creator（可选）

本 skill 已完整覆盖：触发条件、核心原则、端到端架构、关键代码、错误案例、验证清单、排查 flowchart。如需写测试用例或量化评估，可调用 skill-creator。
