---
name: flutter-home-widget-realtime-sync
description: Flutter + home_widget 把倒计时类实时值显示到 Android 桌面 AppWidget 的端到端架构。走字由原生 Chronometer 自走（app 零唤醒），Flutter 只在状态切换时推一次。当用户提到 home_widget 不同步、桌面小组件不刷新、appwidget 实时值、widget 显示卡死、widget 进程被杀场景、AppWidgetProvider 找不到、或小组件被判定后台高耗电时触发。
---

# Flutter ↔ Android Home Widget 实时值同步

## 触发场景

用户描述任意以下情况时，本 skill 必须被调用：

- ⚠️ **"app 被判定后台高耗电" / "小组件费电"** → 直接看「原则 2」，
  走字**不要**用 Flutter 1Hz 推送
- "桌面小组件不同步" / "widget 不刷新" / "首页 widget 时间停了"
- "home_widget 调用没反应" / "updateWidget 不触发 onUpdate"
- "AppWidgetProvider 收不到广播"
- "Flutter 进程被杀后 widget 数据冻结"
- "widget 30 分钟才更新一次" / "只有系统周期才刷"
- "ClassNotFoundException ClockWidgetProvider" 类似报错
- "点击 widget 进入的是首页/列表,想直接进入具体页面"
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

### 原则 2：走字交给原生 `Chronometer`，Flutter 只在状态切换时推

> ⚠️ **这一条是 2026-09 重构后的结论。旧实现是「Flutter 每秒 push 一次」，
> 已被系统判定为「后台高耗电」，不要再退回那个做法。**
>
> 旧实现的问题：`HomeWidget.saveWidgetData` 底层是 **`commit()`（同步落盘）**，
> 不是 `apply()`。所以 1Hz push 每秒要做 6~10 次磁盘提交 + 1 次广播唤醒
> 桌面 host 进程重建 RemoteViews。app 在后台时这个开销照跑，正是省电统计里
> 最显眼的「高频唤醒 + 频繁写盘」形态。

正确的分层：

| 层  | 触发        | 数据源                          | 职责      |
| --- | ----------- | ------------------------------- | --------- |
| L1  | **桌面侧 `Chronometer` 自走** | 推送时下发的 `base` 锚点 | 运行中的秒级走字，**app 零唤醒** |
| L2  | Flutter 状态切换（start/pause/reset/归零） | Provider 内存快照 | 重新下发锚点 / 切回静态文本 |
| L3  | 系统 onUpdate / 用户点 🔄 | 原生侧基于 `startTimeMs` 重算 | Flutter 已死时的自愈 |

实现要点：
- **L1**：布局里放 `Chronometer`（`visibility=gone`）与静态 `TextView` 二选一。
  运行中 `setChronometerCountDown(id, true)` → `setChronometer(id, base, null, true)`
  并把 Chronometer 设为 VISIBLE；其余状态 `setChronometer(..., started=false)`
  + TextView VISIBLE。
- **L2**：Provider 写 `clock_start_time_ms` + `clock_start_remaining_seconds`，
  原生据此算 `base`。Flutter 侧 tick **不做任何 I/O**。
- **L3**：XML 加 `🔄` TextView，`PendingIntent.getBroadcast(context, appWidgetId, ACTION_REFRESH_intent, FLAG_IMMUTABLE)` 触发自己的 `onReceive`

#### Chronometer 的几个硬约束（都踩过）

**1. `base` 必须锚在 `SystemClock.elapsedRealtime()`，不能用 `uptimeMillis`。**

```kotlin
val remainingMs = startRemaining * 1000L - (System.currentTimeMillis() - startTimeMs)
val base = SystemClock.elapsedRealtime() + remainingMs   // 含深睡眠
```

`uptimeMillis` 不含深睡眠，倒计时会在息屏时"停住"。`elapsedRealtime` 与
`currentTimeMillis` 都含深睡眠，差值自动抵消 —— 所以**设备休眠对 base 无影响**，
这正是 Chronometer 方案相对 1Hz 推送的核心优势。

`base` 是绝对锚点，与 host 何时 apply 无关，**不需要持久化**，每次 update 重算即可。
但它是 boot 相对的：**重启后失效**，依赖开机后系统补发 `ACTION_APPWIDGET_UPDATE`
→ `onUpdate` 重算恢复。

**2. 不要 `setFormat("-%s")` 来显示超时 —— 会变成 `--00:12`。**

Chronometer 数到 0 **不会自停**，越过 0 后框架自动取绝对值并套
`R.string.negative_duration`（`-%s`）渲染负号。所以**全程 `countDown=true` +
`format=null`** 即可覆盖负数，共用一个 Chronometer、无需任何模式切换。

**3. action 顺序：`setChronometer` 在前，`setChronometerCountDown` 在后。**

```kotlin
setChronometer(viewId, base, null, true)      // ← 先
setChronometerCountDown(viewId, true)          // ← 后
```

与官方文档 / 社区用法一致。**不要反过来写**（这个坑踩过：曾按"countDown 要先落，
否则 updateText 读不到"的推理把顺序写反了）。两种顺序的稳健性不对称：

- 若 `ChronometerAction.apply` 用自带的 countDown 字段无条件
  `chronometer.setCountDown(...)`（4 参重载传的是 `false`），"countDown 在前"
  会被随后的 `setChronometer` 覆盖 → **变成向上计数，倒计时反向走字**。
- 反过来若它不碰 countDown，两种顺序都对。

所以只有"setChronometer 在前"在两种实现下都正确。中间那个"向上计数"的瞬时态
不可见 —— RemoteViews 整批 action 应用完才绘制，且 `setCountDown()` 自己会调
`updateText()` 立刻纠正文本。

**4. `setChronometerCountDown` 是 API 24**（不是网上说的 17），minSdk 必须 ≥ 24。

**5. 显示格式由 `DateUtils.formatElapsedTime` 决定，补不了前导零。**

| 剩余 | Chronometer 渲染 |
| --- | --- |
| 330s | `05:30`（<1h 时小时段整个消失） |
| 3661s | `1:01:01`（≥1h 小时**不补零**） |
| -12s | `-00:12` |

Java `Formatter` 对字符串没有零填充，`%s` 前加 `0` 也只是字面量 —— 这是硬约束，
产品侧需提前知会。静态 TextView 分支仍可用自己的 `formatHms()` 保留 `00:05:30`。

### 原则 3：并发推送要「最新帧必胜」，不要「还在写就跳过」

```dart
static Future<void> _chain = Future<void>.value();
static ClockWidgetData? _pending;

static Future<void> updateClockWidget(ClockWidgetData data) {
  _pending = data;                       // 新帧覆盖尚未写出的旧帧
  _chain = _chain.then((_) async {
    final next = _pending;
    if (next == null) return;
    _pending = null;
    try {
      await _write(next);
    } catch (e, stack) {
      debugPrint('[Service] failed: $e\n$stack');
    }
  });
  return _chain;
}
```

**不要用 `if (_isUpdating) return;` 去重** —— 那是"丢掉最新帧"：`startCountdown`
的推送还在飞时用户立刻点暂停，暂停态就永远写不出去，widget 会顽固地卡在
「进行中」。改低频推送后单次丢失更显眼，必须用合并链保证最终态一定写出。

`_write()` 里仍用 `Future.wait` 并发写多个 key（比顺序 await 快约 N 倍）。

**只下发原生真正会读的 key**。多写一个 key 就是多一次同步磁盘提交。本项目
clock widget 从 10 个收敛到 6 个（删掉了 `clock_duration_seconds` /
`clock_color` / `clock_formatted_time` / `clock_is_overtime` —— 前两个原生
从不读，后两个是原生自算的时变量）。新增 key 必须两边同时改，否则静默失效。

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
│   ├─ Timer.periodic(1s)       │ 仅状态  │   ├─ onUpdate(ids)            │
│   │   └─ 纯内存 tick，无 I/O  │ 切换时  │   │   └─ updateAppWidget × N  │
│   ├─ _syncToWidget()          │────────>│   ├─ onReceive(ACTION_REFRESH)│
│   │   只在 start/pause/reset/ │  推一次 │   │   └─ updateAppWidget × N  │
│   │   归零 时调用             │         │   └─ updateAppWidget(ctx, id) │
│   ├─ ClockWidgetService       │         │       ├─ getData(prefs)       │
│   │   └─ updateWidget(        │         │       ├─ remainingMs =        │
│   │       qualifiedAndroidName│         │       │   startRemain*1000 -  │
│   │     )                     │         │       │   (now - st)   [毫秒!]│
│   └─ WidgetsBindingObserver   │         │       ├─ base =              │
│       ├─ paused: 停 tick +    │         │       │   elapsedRealtime()+  │
│       │   落盘 + 推一次 +     │         │       │     remainingMs       │
│       │   releaseAllBeats()   │         │       └─ Chronometer 自走字   │
│       └─ resumed: 补算 +      │  load   │          (app 零唤醒)         │
│           补播归零音 + 推一次 │<────────│                              │
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

  // 「最新帧必胜」的串行合并链（**不是** if (_isUpdating) return;）
  static Future<void> _chain = Future<void>.value();
  static ClockWidgetData? _pending;

  static Future<void> updateClockWidget(ClockWidgetData data) {
    _pending = data;
    _chain = _chain.then((_) async {
      final next = _pending;
      if (next == null) return;
      _pending = null;
      try {
        await _write(next);
      } catch (e, stack) {
        debugPrint('[ClockWidgetService] failed: $e\n$stack');
      }
    });
    return _chain;
  }

  static Future<void> _write(ClockWidgetData data) async {
    await Future.wait([
      // 只写原生真正会读的 6 个 key（多写一个 = 多一次同步磁盘 commit）
      HomeWidget.saveWidgetData('clock_title', data.title),
      HomeWidget.saveWidgetData('clock_remaining_seconds', data.remainingSeconds.toString()),
      HomeWidget.saveWidgetData('clock_is_running', data.isRunning ? '1' : '0'),
      HomeWidget.saveWidgetData('clock_start_time_ms', data.startTimeMs.toString()),
      HomeWidget.saveWidgetData('clock_start_remaining_seconds', data.startRemainingSeconds.toString()),
      HomeWidget.saveWidgetData('clock_is_paused_at_start', data.isPausedAtStart ? '1' : '0'),
    ]);
    await HomeWidget.updateWidget(qualifiedAndroidName: _qualifiedAndroidName);
  }
}
```

### B. Provider 冷启动同步（src: `lib/main.dart` + `lab_clock_provider.dart`）

```dart
// main.dart
classic_provider.ChangeNotifierProvider(
  lazy: false,                        // 冷启动即建，否则 widget 要等进页面才同步
  create: (_) => LabClockProvider(),
),

// LabClockProvider
LabClockProvider() {
  _startTimer();                              // 1Hz tick —— 纯内存，**不做 I/O**
  WidgetsBinding.instance.addObserver(this);  // 监听 paused / resumed
  loadClocks();                               // 冷启动即加载 + 首次 sync
  // ★ 这里**不要**再调 MetronomeService.instance.ensureReady()：
  //   Oboe 是 LowLatency+Exclusive 流，冷启动打开会让音频 HAL 全程常驻、
  //   阻止 CPU 深度睡眠。现由 MetronomeService 按需初始化 + 空闲 30s 自关。
}
```

### C. `_onTick` —— 每秒只碰内存，不写盘不推送

```dart
void _onTick() {
  var changed = false, crossed = false;
  final now = DateTime.now();
  for (var i = 0; i < _clocks.length; i++) {
    final next = tickRemaining(_clocks[i], now);   // 纯函数，可单测
    if (next == null) continue;
    if (crossedZero(_clocks[i].remainingSeconds, next)) crossed = true;
    _clocks[i] = _clocks[i].copyWith(remainingSeconds: next);
    changed = true;
  }
  if (!changed) return;

  // 只有归零这一次「真正的状态迁移」才落盘 + 推 widget
  if (crossed) {
    ClockAlertSound.instance.play();
    _saveClocks();
    _syncToWidget();
  }
  if (_isForeground) notifyListeners();
}
```

**安全性依据**：`remainingSeconds` 只是派生显示值 —— 重算锚点
`startTime` + `startRemainingSeconds` 在 `startCountdown` 时就已持久化，
`_recalculateRunningClocks()` 用的是 `startRemainingSeconds ?? durationSeconds
?? remainingSeconds`，运行中的 clock 恒命中第一分支。所以删掉每 tick 落盘不会
丢状态。**纪律**：`startCountdown` / `pauseCountdown` / `resetCountdown` /
`updateTime` 里的 `await _saveClocks()` 一个都不能删。

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

## 引用索引(按需加载)

主 SKILL.md 聚焦"实时值同步"的核心架构(qualifiedAndroidName / 三层兜底 / 并发写 / 冷启动同步 / 多实例 requestCode)。
两类 widget 端专项已沉淀到独立 ref,按需加载:

| ref | 何时读取 | 路径 |
| --- | --- | --- |
| [[widget-click-deeplink]] | widget 主体点击 → 直达 Flutter 具体 demo 页面;`fr://` 深链 + MethodChannel + FrNavigator 整链路;首次给新 widget 加点击跳转 | references/widget-click-deeplink.md |
| [[widget-style-spec]] | 设计或修改 widget layout/xml 之前;去 emoji、支持 1×1、launcher 兼容、layout 自适应 | references/widget-style-spec.md |
| [[widget-label-and-manifest]] | widget picker label 全是 "小豆子" 无法区分 / 加 `android:label` `description` `previewLayout` / autostart flag 模式 / MethodChannel 翻译表抽取 | references/widget-label-and-manifest.md |

**加载触发关键词**:

- "widget 点击 / widget 直达 / widget 跳转 / 点击进首页 / 点击直达 demo"
  → [[widget-click-deeplink]]
- "widget 样式优化 / 去掉 emoji / 支持 1×1 / widget 太大 / launcher 兼容性"
  → [[widget-style-spec]]
- "widget 都是小豆子 / widget 没法区分 / picker 显示一样 / 给 widget 加 label / widget label 命名"
  → [[widget-label-and-manifest]]

## 调用 skill-creator（可选）

本 skill 已完整覆盖：触发条件、核心原则、端到端架构、关键代码、错误案例、验证清单、排查 flowchart。如需写测试用例或量化评估，可调用 skill-creator。
