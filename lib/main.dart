import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart' as classic_provider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/providers.dart';
import 'screens/home/home_page.dart';
import 'screens/gallery/gallery_manage_page.dart';
import 'screens/profile/profile_page.dart';
import 'screens/lab/lab_page.dart';
import 'core/focus/focus_home_page.dart';
import 'core/focus/providers/focus_provider.dart';
import 'core/timetable/timetable.dart';
import 'lab/lab_container.dart';
import 'widgets/xiaodouzi_bottom_bar.dart';
import 'lab/demos/grid_dashboard_demo.dart';
import 'lab/demos/notebook_demo_ai_proto.dart';
import 'lab/demos/clock_demo.dart';
import 'lab/demos/network_demo.dart';
import 'lab/demos/game_2048_demo.dart';
import 'lab/demos/free_canvas_demo.dart';
import 'lab/demos/drag_reorder_demo.dart';
import 'lab/demos/web_bookmark_demo.dart';
import 'lab/demos/storage_analyze_demo.dart';
import 'lab/demos/hexagon_panel_demo.dart';
import 'lab/demos/typewriter_demo.dart';
import 'lab/demos/snake_game_demo.dart';
import 'lab/demos/api_test_demo.dart';
import 'lab/demos/calendar_demo.dart';
import 'lab/demos/my_diary_header_demo.dart';
import 'lab/demos/water_capsule_demo.dart';
import 'lab/providers/lab_note_provider.dart';
import 'lab/providers/lab_clock_provider.dart';
import 'providers/agent_chat_provider.dart';
import 'core/theme/app_theme.dart';

void main() async {
  // 确保 Flutter 绑定初始化
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 Hive
  final hiveRepo = HiveTimetableRepository();
  await hiveRepo.init();

  // 注册 Demo 页面
  // 注册 Demo 页面
  registerGridDashboardDemo();
  registerNotebookDemoAiProto();
  registerClockDemo();
  registerNetworkDemo();
  registerGame2048Demo();
  registerFreeCanvasDemo();
  registerDragReorderDemo();
  registerWebBookmarkDemo();
  registerStorageAnalyzeDemo();
  registerHexagonPanelDemo();
  registerTypewriterDemo();
  registerSnakeGameDemo();
  registerApiTestDemo();
  registerCalendarDemo();
  registerMyDiaryHeaderDemo();
  registerWaterCapsuleDemo();

  // 使用 ProviderScope 包装应用，注入 Repository
  runApp(
    ProviderScope(
      overrides: [
        TimetableStore.repoProvider.overrideWithValue(hiveRepo),
      ],
      child: const MyApp(),
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
  static const _channel = MethodChannel(
    'com.example.flutter_application_1/widget',
  );
  String? _pendingRoute;
  late ThemeProvider _themeProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler(_handleMethodCall);
    _themeProvider = ThemeProvider()..init();

    // 加载课表数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(TimetableStore.provider.notifier).hydrate();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'navigateToLab') {
      _navigateToLab();
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 导航到 Lab 页面
  static void navigateToLab() {
    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => const LabPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return classic_provider.MultiProvider(
      providers: [
        classic_provider.ChangeNotifierProvider.value(value: _themeProvider),
        classic_provider.ChangeNotifierProvider(create: (_) => MessageProvider()),
        classic_provider.ChangeNotifierProvider(create: (_) => LabNoteProvider()),
        classic_provider.ChangeNotifierProvider(create: (_) => LabClockProvider()),
        classic_provider.ChangeNotifierProvider(create: (_) => AIChatProvider()),
        classic_provider.ChangeNotifierProvider(create: (_) => AgentChatProvider()),
        classic_provider.ChangeNotifierProvider(create: (_) => FocusProvider()..init()),
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

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final PageController _pageController = PageController();

  final List<Widget> _pages = const [
    ProfilePage(), // 0: 主页（用户页面）
    HomePage(), // 1: 聊天
    FocusHomePage(), // 2: O - 专注计时器
    GalleryManagePage(), // 3: 图库
  ];

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _onItemTapped(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _onAddPressed() {
    // O按钮 - 导航到专注计时器页面（索引2）
    _pageController.animateToPage(
      2,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        children: _pages,
      ),
      bottomNavigationBar: XiaoDouZiBottomBar(
        currentIndex: _selectedIndex,
        onItemSelected: _onItemTapped,
        onAddPressed: _onAddPressed,
      ),
    );
  }
}

/// 待开发页面占位符
class _DevPage extends StatelessWidget {
  const _DevPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.construction_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              '功能待开发',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}
