import 'package:flutter/material.dart' hide RichText;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart' as classic_provider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rive/rive.dart' hide Animation;
import 'providers/providers.dart';
import 'screens/chat/home_page.dart';
import 'lab/lab_bootstrap.dart';
import 'lab/lab_container.dart';
import 'screens/profile/profile_page.dart';
import 'screens/profile/lab/lab_page.dart';
import 'core/focus/focus_home_page.dart';
import 'core/focus/providers/focus_provider.dart';
import 'core/timetable/timetable.dart';
import 'widgets/xiaodouzi_bottom_bar.dart';
import 'core/schema/schema.dart';
import 'lab/demos/clock/providers/lab_clock_provider.dart';
import 'lab/demos/calendar/providers/lab_calendar_provider.dart';
import 'core/body/models/body_record_repo.dart';
import 'core/line/io/supabase_config.dart';
import 'services/message_strategy/di/di.dart';
import 'core/note/note_root_scope.dart';
void main() async {
  // 确保 Flutter 绑定初始化
  WidgetsFlutterBinding.ensureInitialized();
  await RiveNative.init();

  // 初始化 Hive
  final hiveRepo = HiveTimetableRepository();
  await hiveRepo.init();
  await bodyRecordRepo.init();

  // 初始化 Supabase
  await SupabaseConfig.init();

  // 初始化 Lab 模块（注册所有 Demo + Schema）
  bootstrapLab();

  // 初始化消息策略
  registerMessageStrategies();

  // 初始化笔记模块
  final noteRoot = NoteFactory.create();

  // 使用 NoteRootScope 包裹应用根节点
  runApp(
    NoteRootScope(
      noteRoot: noteRoot,
      child: ProviderScope(
        overrides: [TimetableStore.repoProvider.overrideWithValue(hiveRepo)],
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

    // 初始化 Schema 导航器
    SchemaNavigator.setNavigatorKey(navigatorKey);

    // 加载课表数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(TimetableStore.provider.notifier).hydrate();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'navigateToLab') {
      _navigateToLab();
    } else if (call.method == 'navigateToCalendar') {
      _navigateToCalendar();
    }
  }

  void _navigateToLab() {
    // 延迟执行确保 navigatorKey 已初始化
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const LabPage()),
      );
    });
  }

  void _navigateToCalendar() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 确保日历 demo 已注册
      final calendarDemo = demoRegistry.get('日历待办');
      if (calendarDemo == null) return;
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => _CalendarDeepLinkPage(demo: calendarDemo),
        ),
      );
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
              // 处理深层链接 fr://lab -> /lab
              if (settings.name == '/lab') {
                return MaterialPageRoute(
                  builder: (_) => const LabPage(),
                  settings: settings,
                );
              }
              // 默认路由
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

/// 桌面小组件深层链接：直接打开日历 demo 页面
class _CalendarDeepLinkPage extends StatelessWidget {
  final DemoPage demo;

  const _CalendarDeepLinkPage({required this.demo});

  @override
  Widget build(BuildContext context) {
    return demo.buildPage(context);
  }
}

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

