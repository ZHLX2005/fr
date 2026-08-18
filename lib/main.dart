import 'package:flutter/material.dart' hide RichText;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart' as classic_provider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rive/rive.dart' hide Animation;
import 'core/theme/theme_provider.dart';
import 'services/ai_chat/ai_chat_provider.dart';
import 'services/ai_chat/agent_chat_provider.dart';
import 'screens/chat/home_page.dart';
import 'lab/lab_bootstrap.dart';
import 'screens/profile/profile_page.dart';
import 'core/focus/focus_home_page.dart';
import 'core/focus/providers/focus_provider.dart';
import 'core/timetable/timetable.dart';
import 'widgets/xiaodouzi_bottom_bar.dart';
import 'core/schema/schema.dart';
import 'lab/demos/clock/providers/lab_clock_provider.dart';
import 'core/storage/hive/body_record_repository.dart';
import 'core/line/io/supabase_config.dart';
import 'services/message_strategy/di/di.dart';
import 'core/note/note_root_scope.dart';
import 'core/share_receive/share_receive_store.dart';
import 'native/home_widget/timetable_widget_syncer.dart';
import 'services/apk_download_service.dart';

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
  await RiveNative.init();

  // 初始化 APK 后台下载服务（Android Foreground Service）
  await ApkDownloadService().initialize();

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

  // ★ 注册桌面 widget MethodChannel（在 runApp 前注册，handler 在 widget 树之外也可调用）
  const channel = MethodChannel(_kWidgetChannel);
  channel.setMethodCallHandler(_handleRootMethodCall);

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

/// Task 8: `_CalendarDeepLinkPage` 已删除 — 日历入口统一走
/// `fr://lab/demo/calendar` -> frRouter -> LabDemoHandler。
/// `NotionImageHostDeepLinkPage` 整体搬到
/// `lib/core/schema/handlers/notion_image_host_handler.dart`。

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;

  // RepaintBoundary 缓存渲染层，Transform 平移时只移 GPU 图层
  final List<Widget> _pages = const [
    RepaintBoundary(child: ProfilePage()),    // 主页（左）
    RepaintBoundary(child: FocusHomePage()),  // Time（中）
    RepaintBoundary(child: HomePage()),       // AI 助手（右）
  ];

  late final AnimationController _ctrl;
  late final CurvedAnimation _pageCurve;
  bool _isAnimating = false;
  int _toIndex = 0;

  @override
  void initState() {
    super.initState();
    // 预热 banner 路径，消除首页切换时 ProfilePage State 重建的占位帧（fr #3）
    HomeBannerCache.warmUp();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _pageCurve = CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeInOutQuint,
    );
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _selectedIndex = _toIndex;
          _isAnimating = false;
        });
        _ctrl.reset();
      }
    });
  }

  @override
  void dispose() {
    _pageCurve.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    if (index == _selectedIndex || _isAnimating) return;
    _startTransition(index);
  }

  void _onAddPressed() {
    if (_isAnimating) return;
    _startTransition(2);
  }

  void _startTransition(int target) {
    _toIndex = target;
    _isAnimating = true;
    setState(() {});
    _ctrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          return Stack(
            children: [
              // 底层：目标页面（静止不动）
              SizedBox(
                width: w,
                child: _pages[_isAnimating ? _toIndex : _selectedIndex],
              ),
              // 覆盖层：双页同时平移（传送带效果）
              if (_isAnimating)
                AnimatedBuilder(
                  animation: _pageCurve,
                  builder: (context, _) {
                    final isForward = _toIndex > _selectedIndex;
                    final t = _pageCurve.value;
                    // 新页从异侧滑入，旧页往同侧滑出
                    final newDx = isForward ? (1 - t) * w : -(1 - t) * w;
                    final oldDx = isForward ? -t * w : t * w;
                    return SizedBox(
                      width: w,
                      child: Stack(
                        children: [
                          Transform.translate(
                            offset: Offset(newDx, 0),
                            child: SizedBox(width: w, child: _pages[_toIndex]),
                          ),
                          Transform.translate(
                            offset: Offset(oldDx, 0),
                            child: SizedBox(width: w, child: _pages[_selectedIndex]),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
      bottomNavigationBar: XiaoDouZiBottomBar(
        currentIndex: _isAnimating ? _toIndex : _selectedIndex,
        onItemSelected: _onItemTapped,
        onAddPressed: _onAddPressed,
      ),
    );
  }
}

/// fr:// URL 翻译器 —— 把原生 MethodChannel call(method + args)翻译成
/// 项目内统一路由 URL,供 main.dart 的 _handleMethodCall 调用。
///
/// 设计目的:
///   - 翻译表与 `bootstrap_routes.dart` 的注册表同目录可见
///   - 加新 widget → 改这一个文件 + bootstrap_routes + handler,不需进 main.dart
///   - 防腐蚀:把"method name → fr:// URL"的唯一映射关系收口到本文件
///
/// 调用约定:
///   返回 null 表示该 method 不归本层管(常见情况:notImplemented);
///   调用方应保留旧行为:不 push、不抛错。
///
/// 已支持的 method(与 WidgetChannel.kt 的 when 分支严格对称):
///   navigateToLab              → fr://lab
///   navigateToCalendar         → fr://lab/demo/calendar
///   navigateToClock            → fr://lab/demo/clock
///   navigateToTimetable        → fr://timetable
///   navigateToNotionImage      → fr://notion/image-host?autocapture=<bool>
///   navigateToRecorder         → fr://lab/demo/recorder?autostart=<bool>
///   navigateToClockWidgetToggle→ fr://clock/widget-toggle
///   shareReceived              → fr://share/receive（载荷存 ShareReceiveStore.pending）
class FrMethodChannelTranslator {
  FrMethodChannelTranslator._();

  /// 同步翻译:输入 call,返回 fr:// URL 或 null。
  ///
  /// 不读 clock / context,纯字符串拼接 + 类型断言 —— 单元可测。
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
      'navigateToClockWidgetToggle' => 'fr://clock/widget-toggle',
      'shareReceived' => _translateShareReceived(call.arguments),
      _ => null,
    };
  }

  /// 分享接收：原生传 `{text: String?, files: List<String>}`，
  /// 载荷经 URL 不便传输（文本长/含特殊字符），存入
  /// [ShareReceiveStore.pending] 供 handler 页面消费，URL 仅作导航信号。
  static String? _translateShareReceived(Object? arguments) {
    final map = (arguments as Map?)?.cast<String, dynamic>() ?? const {};
    ShareReceiveStore.pending = ShareReceiveData(
      text: map['text'] as String?,
      fileUris: (map['files'] as List?)?.cast<String>() ?? const [],
    );
    return 'fr://share/receive';
  }
}