import 'package:flutter/material.dart' hide RichText;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart' as classic_provider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rive/rive.dart' hide Animation;
import 'providers/providers.dart';
import 'screens/chat/home_page.dart';
import 'lab/lab_bootstrap.dart';
import 'screens/profile/profile_page.dart';
import 'core/focus/focus_home_page.dart';
import 'core/focus/providers/focus_provider.dart';
import 'core/timetable/timetable.dart';
import 'widgets/xiaodouzi_bottom_bar.dart';
import 'core/schema/schema.dart';
import 'core/schema/fr_navigator.dart';
import 'core/schema/bootstrap_routes.dart';
import 'lab/demos/clock/providers/lab_clock_provider.dart';
import 'lab/demos/calendar/providers/lab_calendar_provider.dart';
import 'core/body/models/body_record_repo.dart';
import 'core/line/io/supabase_config.dart';
import 'services/message_strategy/di/di.dart';
import 'core/note/note_root_scope.dart';
import 'native/home_widget/timetable_widget_syncer.dart';
import 'services/apk_download_service.dart';
void main() async {
  // 确保 Flutter 绑定初始化
  WidgetsFlutterBinding.ensureInitialized();
  await RiveNative.init();

  // 初始化 APK 后台下载服务（Android Foreground Service）
  await ApkDownloadService().initialize();

  // 初始化 Hive
  final hiveRepo = HiveTimetableRepository();
  await hiveRepo.init();
  await bodyRecordRepo.init();

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

  /// 桌面 widget MethodChannel 回调 — 翻译 4 个 method name 到 fr:// URL，
  /// 统一走 FrNavigator.handle 分发（FrNavigator 内部已用 RouteSettings.name
  /// 实现防重复堆叠）。
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    final frUrl = switch (call.method) {
      'navigateToLab' => 'fr://lab',
      'navigateToCalendar' => 'fr://lab/demo/calendar',
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
        classic_provider.ChangeNotifierProvider(
          create: (_) => MessageProvider(),
        ),
        // lazy:false → 冷启动即创建，立即 loadClocks + _syncToWidget。
        // 否则桌面 widget 要等用户进入 ClockDemo 页面才会被同步。
        classic_provider.ChangeNotifierProvider(
          lazy: false,
          create: (_) => LabClockProvider(),
        ),
        // 同理：日历 widget 也要冷启动同步
        classic_provider.ChangeNotifierProvider(
          lazy: false,
          create: (_) => LabCalendarProvider(),
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
      child: classic_provider.Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            navigatorKey: navigatorKey,
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

