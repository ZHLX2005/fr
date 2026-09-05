import 'dart:async';

import 'package:flutter/material.dart' hide RichText;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart' as classic_provider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rive/rive.dart' hide Animation;
import 'core/theme/state/theme_provider.dart';
import 'services/ai_chat/ai_chat_provider.dart';
import 'services/ai_chat/agent_chat_provider.dart';
import 'lab/lab_bootstrap.dart';
import 'core/focus/providers/focus_provider.dart';
import 'core/timetable/timetable.dart';
import 'core/schema/schema.dart';
import 'lab/demos/clock/providers/lab_clock_provider.dart';
import 'core/storage/hive/body_record_repository.dart';
import 'services/message_strategy/di/di.dart';
import 'core/ai_chat/system_messages/system_events_controller.dart';
import 'core/note/note_root_scope.dart';
import 'native/home_widget/timetable_widget_syncer.dart';
import 'services/apk_download_service.dart';
import 'app_lifecycle/fr_method_channel_translator.dart';
import 'app_lifecycle/apk_startup_hook.dart';
import 'app_lifecycle/crash_log_startup_hook.dart';
import 'app_lifecycle/main_screen.dart';
import 'core/chess/chess.dart';

/// 全局 Navigator Key（桌面 widget MethodChannel 跳转需要）
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// 桌面 widget MethodChannel 名（与 Kotlin 端 WidgetChannel.kt 对齐）
const _kWidgetChannel = 'io.github.xiaodouzi.fr/widget';

/// 桌面 widget MethodChannel 回调 —— 走 FrMethodChannelTranslator，
/// 统一经 FrNavigator.handle 分发（CLEAR_TOP 防栈累加）。
Future<dynamic> _handleRootMethodCall(MethodCall call) async {
  final frUrl = FrMethodChannelTranslator.translate(call);
  if (frUrl == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    FrNavigator.handle(rootNavigatorKey.currentContext, frUrl);
  });
}

void main() async {
  // 确保 Flutter 绑定初始化
  WidgetsFlutterBinding.ensureInitialized();

  // 注册国际象棋皮肤（const catalog → RemoteChessSkin）。
  // 必须在任何 chess UI 构建之前调用；这里走"启动期一次性"语义。
  // KV 覆盖不在启动期拉取（避免冷启动网络请求）：改为每次进入
  // 换肤设置页时按需拉取（见 ChessSkinSettingsPage.initState）。
  ChessSkinBundle.registerHardcoded();

  // ★ Layer-2 修复：FrNavigator.handle 内部依赖的 _navigatorKey static 字段
  // 必须由 setNavigatorKey() 显式注入,否则任何 FrNavigator.handle(...) 走到
  // `final nav = _navigatorKey?.currentState; if (nav == null) return;` 时
  // 会早 return;以及 handler.build 在 context 为 null 时回退到
  // `_placeholderContext()` = `_navigatorKey!.currentContext!` —— *!* 解
  // 引用 null 抛 NullCheckError,被 handle try/catch 吞掉只 print一行。
  // 历史根因：commit 235eabd3 把 _MyAppState 改成 ConsumerWidget(无 initState),
  // 原本在 initState 里调用的 FrNavigator.setNavigatorKey(navigatorKey) 被
  // 一起删掉,之后没人再注入 —— analyze 不查 runtime call graph,CI 漏检,
  // 直到 widget deep-link 全面失效才暴露。
  FrNavigator.setNavigatorKey(rootNavigatorKey);

  // ★ cold-start race fix：把桌面 widget MethodChannel 的 handler 注册
  // 与 frRouter 路由注册提前到任何 await 之前。
  //
  // 时序根因：冷启动 widget 点击 → MainActivity.onResume 立即
  // invokeMethod("navigateToClock") 等。等价于 Flutter 引擎在 Dart 侧
  // DefaultBinaryMessenger.handlePlatformMessage 里查 _handlers[channel]：
  // 若 setMethodCallHandler 还没调到,该 channel handler 为 null,
  // 消息会**静默丢弃**（logcat 无报错、无 SnackBar）,用户感受就是
  // "点了 widget,app 打开但停在首页"。一旦 dart main() 跑完 await 链
  // 才注册 handler,之前的 invokeMethod 已丢,补发只能靠 onNewIntent。
  //
  // bootstrapLab + registerAllFrRoutes 是同步操作,放进这里既保证
  // handler 注册时 routing infrastructure 已就绪,又不会拖慢冷启动。
  bootstrapLab();
  registerAllFrRoutes();
  // ★ 注册桌面 widget MethodChannel（必须在 runApp 之前,handler 在 widget 树之外也可调用）
  const channel = MethodChannel(_kWidgetChannel);
  channel.setMethodCallHandler(_handleRootMethodCall);

  await RiveNative.init();

  // 初始化 APK 后台下载服务（Android Foreground Service）
  await ApkDownloadService().initialize();

  // APK 自动下载生命周期：先 hydrate 状态（lastSeenUploadTime / autoDownloadEnabled）
  // 再触发启动期检查；开关关闭时静默返回，不影响冷启动。
  unawaited(runApkAutoDownloadOnStartup());

  // 崩溃日志摄入：启动时一次性把原生侧累积的 crash 日志导入系统消息面板。
  unawaited(runCrashLogIntakeOnStartup());

  // 初始化 Hive
  final hiveRepo = HiveTimetableRepository();
  await hiveRepo.init();
  await bodyRecordRepository.init();

  // 初始化消息策略
  registerMessageStrategies();

  // 系统消息持久化恢复：把上次会话的事件列表从 SharedPreferences 加载
  // 回 SystemEventsController（不 await —— 恢复内部会把磁盘旧事件合并到
  // 已 append 的新事件之前，启动钩子先写入也不会丢）。
  unawaited(SystemEventsController().restore());

  // 初始化笔记模块
  final noteRoot = NoteFactory.create();

  // ★ 创建根 ProviderContainer，把课表仓库注入 Riverpod
  final container = ProviderContainer(
    overrides: [
      TimetableStore.repoProvider.overrideWithValue(hiveRepo),
      TimetableStore.syncerProvider.overrideWithValue(
        const DefaultTimetableWidgetSyncer(),
      ),
    ],
  );

  // ★ 启动前同步预加载：主题从 SharedPreferences 读出、课表 hydrate
  // 这样首帧渲染就能拿到正确主题，避免 flash-to-default。
  await container.read(themeNotifierProvider.notifier).hydrate();
  await container.read(TimetableStore.provider.notifier).hydrate();

  // 使用 NoteRootScope + UncontrolledProviderScope（preloaded container）包裹应用根节点
  runApp(
    NoteRootScope(
      noteRoot: noteRoot,
      child: UncontrolledProviderScope(
        container: container,
        child: const MyApp(),
      ),
    ),
  );
}

/// App 根 widget — ConsumerWidget（无状态，主题走 Riverpod）
class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ★ 主题从 Riverpod 派生 provider 取值（state 变 → 整树重建）
    final themeData = ref.watch(themeDataProvider);
    final themeMode = ref.watch(materialThemeModeProvider);

    return classic_provider.MultiProvider(
      providers: [
        // 主题已迁 Riverpod，这里不再注册 ThemeProvider
        // 其它业务 Provider 仍走 classic_provider（增量迁移策略）
        // lazy:false → 冷启动即创建，立即 loadClocks + _syncToWidget。
        // 否则桌面 widget 要等用户进入 ClockDemo 页面才会被同步。
        classic_provider.ChangeNotifierProvider(
          lazy: false,
          create: (_) => LabClockProvider(),
        ),
        classic_provider.ChangeNotifierProvider(
          create: (_) => AIChatProvider(),
        ),
        classic_provider.ChangeNotifierProvider(
          create: (_) => AgentChatProvider(),
        ),
        classic_provider.ChangeNotifierProvider(
          create: (_) => FocusProvider()..init(),
        ),
      ],
      child: MaterialApp(
        navigatorKey: rootNavigatorKey,
        // fr:// CLEAR_TOP 防栈累加依赖的路由栈跟踪器
        navigatorObservers: [frRouteStack],
        title: '小豆子',
        debugShowCheckedModeBanner: false,
        theme: themeData,
        themeMode: themeMode,
        initialRoute: '/',
        onGenerateRoute: (settings) {
          // Task 8: 删 /lab 特殊分支 — fr://lab 走 frRouter 统一处理。
          return MaterialPageRoute(
            builder: (_) => const MainScreen(),
            settings: settings,
          );
        },
      ),
    );
  }
}
