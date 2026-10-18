# 桌面小组件 Picker Label + Manifest 资源管理

本 ref 沉淀自 2026-08 录音机 widget + 全量修复 widget picker label 实战。

适用任何 **Android AppWidget** 的 `<receiver>` / `appwidget-provider` 资源配置,
以及 widget 相关的资源(string / drawable / layout)管理。

## 何时读这个 ref

- 用户反馈"桌面 widget picker 里只显示 app 图标 + 小豆子,看不出哪个是哪个"
- 第一次给 widget 加 `android:label` / `android:description` / `android:previewLayout`
- 给 widget 加新 string resource、drawable、layout,不确定放哪个目录
- 排查"改了 widget 资源但 picker 还是老样子"(launcher 缓存旧 metadata)
- 批量给项目里所有 widget 统一命名规范

## 铁律 1:每个 widget receiver 必须有独立 `android:label`

### 症状

桌面长按 → widget picker 列表里,所有 widget 都显示:

```
[app 图标]   小豆子
```

用户无法区分"哪个 widget 是时钟、哪个是录音、哪个是拍照"。

### 根因

Android widget picker 的 label 来源是 `<receiver>` 的 `android:label`。
如果省略或写成 `app_name`,所有 widget 共享同一个 label。

```xml
<!-- ❌ 错误:receiver 没 label,fallback 到 application android:label -->
<receiver android:name=".native.widget.ClockWidgetProvider" android:exported="true">
    ...
</receiver>

<!-- ✅ 正确:每个 widget 独立 label,区分功能 -->
<receiver
    android:name=".native.widget.ClockWidgetProvider"
    android:label="@string/widget_label_clock"
    android:exported="true">
    ...
</receiver>
```

### Label 命名规范

统一格式:**`小豆子 · <功能>`**,通过 ` · ` (中点 + 空格) 与 app_name 视觉上对齐。

```xml
<!-- strings.xml -->
<string name="widget_label_clock">小豆子 · 时钟</string>
<string name="widget_label_calendar">小豆子 · 日历</string>
<string name="widget_label_timetable">小豆子 · 课表</string>
<string name="widget_label_notion">小豆子 · 拍照</string>
<string name="widget_label_recorder">小豆子 · 录音</string>
```

放在 `res/values/strings.xml`(与 `app_name` 同文件),
便于一次 review / 一次改一处全部生效。

## 铁律 2:`appwidget-provider` 必须配齐 `description` + `previewLayout`

`android:description` 是 picker 中显示在 label 下方的一行说明,
`android:previewLayout` 是 picker 中右侧的预览缩略图。
两者都不影响功能,但影响**用户对 widget 的第一印象**。

```xml
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:minWidth="40dp"
    android:minHeight="40dp"
    android:minResizeWidth="40dp"
    android:minResizeHeight="40dp"
    android:targetCellWidth="1"
    android:targetCellHeight="1"
    android:updatePeriodMillis="1800000"
    android:initialLayout="@layout/recorder_widget"
    android:previewLayout="@layout/recorder_widget"          <!-- ← 新增 -->
    android:resizeMode="horizontal"
    android:description="@string/widget_description_recorder"  <!-- ← 新增 -->
    android:widgetCategory="home_screen">
</appwidget-provider>
```

strings.xml 对应:

```xml
<string name="widget_description_recorder">一键开始录音</string>
<string name="widget_description_clock">桌面时钟 / 倒计时</string>
```

`previewLayout` 通常与 `initialLayout` 同 layout(开发期复用);
生产期可以专门做一个"静态展示态"layout(去掉录音按钮的红点闪烁等)。

## 铁律 3:`flutter analyze` 不会检查 Android 资源 — 必须 `flutter build apk`

```bash
flutter analyze 2>&1 | grep error   # ← 不会发现 widget label 拼错
flutter build apk --debug           # ← 才会触发 manifest / xml 资源 lint
```

典型症状:

- `strings.xml` 里的 `widget_label_recorder` 拼成 `widget_lable_recorder`
- `appwidget-provider` 的 `android:description` 引用了不存在的 string
- `<receiver>` 写了 `android:label="@string/widget_label_recoder"`(typo)

这些都只在 `flutter build apk` 跑资源合并时报错,且部分 launcher 兼容性问题
(MIUI / OneUI 强制 1×2 占位)完全不会报错,只能真机验证。

**约定**:涉及 widget 的任何 manifest / 资源改动,**先跑 `flutter build apk --debug`**,不要只依赖 analyze。

## 铁律 4:改完 manifest / `appwidget-provider` 必须删旧 widget 实例

> ⚠️ launcher 缓存旧 metadata,改完 picker 看不到新 label / 新 size。

```
[桌面上旧的 ClockWidget 实例]
    ↓
[改 strings.xml + appwidget-provider.xml]
    ↓
[重装 APK]
    ↓
[picker 里仍是"小豆子"(旧 label)] ← launcher 缓存
    ↓
[长按删除旧实例 → 从 picker 重新添加] ← 真正生效
```

详细机理见 [[widget-style-spec]] 末尾"修改 widget 后的强制操作"。

## 铁律 5:纯跳转型 widget 不需要三层兜底

主 SKILL.md 的「三层兜底」(L1 Flutter tick / L2 原生重算 / L3 手动刷新)
是为**带实时值的 widget**(时钟 / 倒计时 / 日历)设计的。

**纯跳转 widget**(点击打开某个页面,带 `?autostart` 参数):
- 不需要 Provider / Timer
- 不需要 SharedPreferences 数据
- 不需要 `ACTION_REFRESH` 自定义广播
- 只需 `PendingIntent.getActivity(... ACTION_VIEW + fr://... + FLAG_IMMUTABLE)`

NotionWidgetProvider / RecorderWidgetProvider 都是这个模式:

```kotlin
internal fun updateAppWidget(context: Context, mgr: AppWidgetManager, id: Int) {
    val views = RemoteViews(context.packageName, R.layout.recorder_widget).apply {
        val openIntent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            data = android.net.Uri.parse("fr://lab/demo/recorder?autostart=true")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openPi = PendingIntent.getActivity(
            context, id, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        setOnClickPendingIntent(R.id.widget_root, openPi)
        setOnClickPendingIntent(R.id.widget_record_btn, openPi)
    }
    mgr.updateAppWidget(id, views)
}
```

仅 `onUpdate` 需要实现,无其他生命周期方法。

## 桌面 widget autostart 模式

适用:用户点 widget → 直接进入页面 + 立即触发某个动作(开始录音 / 拍照)。

**问题**:handler 在 push 页面时调用,但 widget 此时正在 build,controller
还没 attach —— 不能直接 `controller.start()`。

**解法**:pending flag + 页面 mount 时消费,3 步:

### Step 1: 全局 pending flag

```dart
// lib/lab/demos/recorder/recorder_page.dart
final ValueNotifier<bool> _pendingAutoStart = ValueNotifier(false);

void markRecorderAutoStart() {
  _pendingAutoStart.value = true;
}
```

### Step 2: Handler 标记 flag(不同步触发 controller)

```dart
class RecorderHandler extends FrRouteHandler {
  @override
  Widget build(BuildContext context, FrRouteMatch match) {
    if (match.queryBool('autostart')) {
      markRecorderAutoStart();   // ← 仅标记,等 page mount
    }
    return const RecorderDemoPage();
  }
}
```

### Step 3: Page mount 后消费

```dart
class _RecorderDemoPageState extends State<RecorderDemoPage> {
  bool _autoStartConsumed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_autoStartConsumed && _pendingAutoStart.value) {
      _autoStartConsumed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _controller.start();   // ← 此时 controller 已 attach,UI 已就绪
      });
    }
  }
}
```

**为什么不能直接 `await controller.start()`**:

- handler build 阶段 controller 还没创建(`RecorderDemoPage` 才刚构造)
- 直接 await → 拿到 null 引用 / 权限未 probe / UI 未 mount 三连坑

`addPostFrameCallback` 等当前帧渲染结束,所有 initState 都跑完,再触发。

## MethodChannel 翻译表抽取到 schema 层

主 SKILL.md + [[widget-click-deeplink]] 都强调"`navigateToXxx` 三件套要对齐"。
但翻译表(`call.method → fr:// URL`)散落在 `main.dart` 的 switch 里,
加新 widget 必须同时改 main.dart + bootstrap_routes,易漏。

**正确做法**:把 switch 表抽到 `core/schema/method_channel_translator.dart`,
与 `bootstrap_routes.dart` 同目录可见:

```dart
// lib/core/schema/method_channel_translator.dart
class FrMethodChannelTranslator {
  FrMethodChannelTranslator._();

  static String? translate(MethodCall call) {
    return switch (call.method) {
      'navigateToLab' => 'fr://lab',
      'navigateToCalendar' => 'fr://lab/demo/calendar',
      'navigateToClock' => 'fr://lab/demo/clock',
      'navigateToTimetable' => 'fr://timetable',
      'navigateToNotionImage' =>
        'fr://notion/image-host?autocapture=${(call.arguments as bool?) ?? false}',
      'navigateToRecorder' =>
        'fr://lab/demo/recorder?autostart=${(call.arguments as bool?) ?? true}',
      _ => null,
    };
  }
}
```

```dart
// lib/main.dart
Future<dynamic> _handleMethodCall(MethodCall call) async {
  final frUrl = FrMethodChannelTranslator.translate(call);
  if (frUrl == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    FrNavigator.handle(navigatorKey.currentContext, frUrl);
  });
}
```

并在 `core/schema/schema.dart` 导出,统一入口。

## 错误案例

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| `<receiver>` 不写 `android:label` | widget picker 里全部 fallback 到 app_name "小豆子",用户无法区分 | 每个 receiver 加 `android:label="@string/widget_label_xxx"` |
| `widget_label_xxx` 拼写错 | picker 直接显示 app_name,不报错 | strings.xml 写完后跑 `flutter build apk` 触发资源 lint |
| 只改 manifest 不删旧 widget 实例 | launcher 缓存旧 metadata,picker 看不到新效果 | 长按删除桌面旧 widget → 从 picker 重新添加 |
| `appwidget-provider` 缺 `description` + `previewLayout` | picker 中 label 下方无说明,缩略图空白 | 全部 widget 一次性补齐 description + previewLayout |
| 仅跑 `flutter analyze` 不跑 `flutter build apk` | widget label / description 错误 analyze 不会报 | 涉及 manifest / 资源改动,先 `flutter build apk --debug` |
| handler 直接 `await controller.start()` | controller 还没 attach,UI 没 mount,permission 没 probe | pending flag + 页面 mount 后 `addPostFrameCallback` 消费 |
| 把 MethodChannel 翻译表散落在 main.dart | 加新 widget 必须同时改 main.dart + bootstrap_routes,易漏 | 抽到 `core/schema/method_channel_translator.dart`,与 bootstrap_routes 同目录 |

## 验证清单

修改 widget label / manifest / 资源后按序检查:

- [ ] `flutter analyze` 0 error(只能查 Dart,查不到 Android 资源)
- [ ] `flutter build apk --debug` 成功(资源合并 + lint 全过)
- [ ] 所有 `<receiver>` 都有 `android:label`
- [ ] 所有 `appwidget-provider` 都有 `android:description` + `android:previewLayout`
- [ ] strings.xml 里的 `widget_label_*` / `widget_description_*` 命名一致(`widget_label_<slug>` / `widget_description_<slug>`)
- [ ] 长按删除桌面旧 widget 实例,从 picker 重新添加
- [ ] picker 中 label 显示"小豆子 · <功能>",description 显示在下方
- [ ] 桌面点击 widget → 进入 fr:// 深链命中的具体 demo 页面
- [ ] 含 `?autostart=true` 的 widget → 页面 mount 后自动触发对应动作

## 给新 widget 加 label 的 SOP(3 步)

> 适用"新建 widget X → 在 picker 里显示独立名字"的场景。

### Step 1: strings.xml 加 label + description

```xml
<!-- res/values/strings.xml -->
<string name="widget_label_xxx">小豆子 · XXX</string>
<string name="widget_description_xxx">XXX 简介</string>
```

### Step 2: appwidget-provider.xml 加 description + previewLayout

```xml
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    ...
    android:previewLayout="@layout/xxx_widget"
    android:description="@string/widget_description_xxx"
    ...>
</appwidget-provider>
```

### Step 3: AndroidManifest.xml receiver 加 label

```xml
<receiver
    android:name=".native.widget.XxxWidgetProvider"
    android:label="@string/widget_label_xxx"
    android:exported="true">
    ...
</receiver>
```

**主 SKILL.md 不用动** —— widget label / 资源管理是 widget 端专项,在本 ref 沉淀。新 widget 按这 3 步复制即可。