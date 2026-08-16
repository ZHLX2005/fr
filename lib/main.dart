import 'dart:async';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart' as classic_provider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rive/rive.dart' hide Animation;
import 'core/color/theme/theme_provider.dart';
import 'services/ai_chat/ai_chat_provider.dart';
import 'services/ai_chat/agent_chat_provider.dart';
import 'lab/lab_bootstrap.dart';
import 'core/focus/providers/focus_provider.dart';
import 'core/timetable/timetable.dart';
import 'core/schema/schema.dart';
import 'lab/demos/clock/providers/lab_clock_provider.dart';
import 'core/storage/hive/body_record_repository.dart';
import 'core/line/io/supabase_config.dart';
import 'services/message_strategy/di/di.dart';
import 'core/note/note_root_scope.dart';
import 'native/home_widget/timetable_widget_syncer.dart';
import 'services/apk_download_service.dart';
import 'app_lifecycle/fr_method_channel_translator.dart';
import 'app_lifecycle/apk_startup_hook.dart';
import 'app_lifecycle/main_screen.dart';

void main() async {
  // 确保 Flutter 绑定初始化
  WidgetsFlutterBinding.ensureInitialized();
  await RiveNative.init();

  // 初始化 APK 后台下载服务（Android Foreground Service）
  await ApkDownloadService().initialize();

  // APK 自动下载生命周期：先 hydrate 状态（lastSeenUploadTime / autoDownloadEnabled）
  // 再触发启动期检查；开关关闭时静默返回，不影响冷启动。
  unawaited(runApkAutoDownloadOnStartup());

  // 初始化 Hive
  final hiveRepo = HiveTimetableRepository();
  await hiveRepo.init();
  await bodyRecordRepository.init();

  // 初始化 Supabase
  await SupabaseConfig.init();

  // 初始化 Lab 模块（注册所有 Demo + Schema）
  bootstrapLab();

  // Task 8: 注册 fr:// 路由到全局 frRouter（handler 来自 bootstrap_routes.dart）
  registerAllFrRoutes();

  // 初始化消息策略
  registerMessageStrategies();

  // 初始化笔记模块
  final noteRoot = NoteFactory.create();

  // 使用 NoteRootScope 包裹应用根节点
  runApp(
    NoteRootScope(
      noteRoot: noteRoot,
      child: ProviderScope(
        overrides: [
          TimetableStore.repoProvider.overrideWithValue(hiveRepo),
          TimetableStore.syncerProvider.overrideWithValue(
            const DefaultTimetableWidgetSyncer(),
          ),
        ],
        child: const MyApp(),
      ),
    ),
  );
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static const _channel = MethodChannel('io.github.xiaodouzi.fr/widget');
  late ThemeProvider _themeProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler(_handleMethodCall);
    _themeProvider = ThemeProvider()..init();

    // Task 8: 改用 FrNavigator（统一 fr:// URL 分发入口）替换 SchemaNavigator。
    FrNavigator.setNavigatorKey(navigatorKey);

    // 加载课表数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(TimetableStore.provider.notifier).hydrate();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}

  /// 桌面 widget MethodChannel 回调 — 翻译走 `FrMethodChannelTranslator`
  /// (lib/app_lifecycle/fr_method_channel_translator.dart),
  /// 统一经 FrNavigator.handle 分发（FrNavigator 内部按 RouteSettings.name
  /// 做 CLEAR_TOP 防重复堆叠：已在栈中则提到栈顶，不再 push）。
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    final frUrl = FrMethodChannelTranslator.translate(call);
    if (frUrl == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FrNavigator.handle(navigatorKey.currentContext, frUrl);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return classic_provider.MultiProvider(
      providers: [
        classic_provider.ChangeNotifierProvider.value(value: _themeProvider),
        // lazy:false → 冷启动即创建，立即 loadClocks + _syncToWidget。
        // 否则桌面 widget 要等用户进入 ClockDemo 页面才会被同步。
        classic_provider.ChangeNotifierProvider(
          lazy: false,
          create: (_) => LabClockProvider(),
        ),
        // 同理：日历 widget 也要冷启动同步
        // 注：v2 LabCalendarProvider 在 CalendarDemo 内部 MultiProvider 局部创建，
        // 不再作为 app 级单例。
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
      child: classic_provider.Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            // fr:// CLEAR_TOP 防栈累加依赖的路由栈跟踪器
            navigatorObservers: [frRouteStack],
            title: '小豆子',
            debugShowCheckedModeBanner: false,
            theme: themeProvider.themeData,
            themeMode: themeProvider.themeModeValue,
            initialRoute: '/',
            onGenerateRoute: (settings) {
              // Task 8: 删 /lab 特殊分支 — fr://lab 走 frRouter 统一处理。
              return MaterialPageRoute(
                builder: (_) => const MainScreen(),
                settings: settings,
              );
            },
          );
        },
      ),
    );
  }
}