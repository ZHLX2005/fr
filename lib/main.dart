import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/providers.dart';
import 'screens/home/home_page.dart';
import 'screens/friends/friends_page.dart';
import 'screens/profile/profile_page.dart';
import 'screens/lab/lab_page.dart';
import 'lab/lab_container.dart';
import 'widgets/xiaodouzi_bottom_bar.dart';
import 'lab/demos/grid_dashboard_demo.dart';
import 'lab/demos/notebook_demo.dart';
import 'lab/demos/clock_demo.dart';
import 'lab/demos/network_demo.dart';
import 'lab/demos/game_2048_demo.dart';
import 'lab/demos/free_canvas_demo.dart';
import 'lab/demos/drag_reorder_demo.dart';
import 'lab/demos/web_bookmark_demo.dart';
import 'lab/demos/storage_analyze_demo.dart';
import 'lab/demos/hexagon_panel_demo.dart';
import 'lab/demos/ripple_effect_demo.dart';
import 'lab/demos/typewriter_demo.dart';
import 'lab/demos/snake_game_demo.dart';
import 'lab/demos/api_test_demo.dart';
import 'lab/demos/calendar_demo.dart';
import 'lab/demos/my_diary_header_demo.dart';
import 'lab/demos/water_capsule_demo.dart';
import 'lab/demos/notification_demo.dart';
import 'lab/providers/lab_note_provider.dart';
import 'lab/providers/lab_clock_provider.dart';
import 'providers/agent_chat_provider.dart';
import 'core/theme/app_theme.dart';

void main() {
  // 注册 Demo 页面
  registerGridDashboardDemo();
  registerNotebookDemo();
  registerClockDemo();
  registerNetworkDemo();
  registerGame2048Demo();
  registerFreeCanvasDemo();
  registerDragReorderDemo();
  registerWebBookmarkDemo();
  registerStorageAnalyzeDemo();
  registerHexagonPanelDemo();
  registerRippleEffectDemo();
  registerTypewriterDemo();
  registerSnakeGameDemo();
  registerApiTestDemo();
  registerCalendarDemo();
  registerMyDiaryHeaderDemo();
  registerWaterCapsuleDemo();
  registerNotificationDemo();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static const _channel = MethodChannel('com.example.flutter_application_1/widget');
  String? _pendingRoute;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 设置 MethodChannel 监听器
    _channel.setMethodCallHandler(_handleMethodCall);
    // 初始化主题
    _initTheme();
  }

  /// 初始化主题设置
  Future<void> _initTheme() async {
    final themeProvider = context.read<ThemeProvider>();
    await themeProvider.init();
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 可以在这里处理从后台恢复时的深层链接
  }

  /// 导航到 Lab 页面
  static void navigateToLab() {
    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => const LabPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => MessageProvider()),
        ChangeNotifierProvider(create: (_) => LabNoteProvider()),
        ChangeNotifierProvider(create: (_) => LabClockProvider()),
        ChangeNotifierProvider(create: (_) => AIChatProvider()),
        ChangeNotifierProvider(create: (_) => AgentChatProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            title: 'Flutter 聊天应用',
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
    ProfilePage(),  // 0: 主页（用户页面）
    HomePage(),     // 1: 聊天
    SizedBox(),     // 2: +号占位 (由底部栏单独处理)
    FriendsPage(),  // 3: 通讯录
    _DevPage(),     // 4: 待开发
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
    // +号按钮不切换页面
    if (index == 2) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _onAddPressed() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.construction_outlined, color: Colors.grey),
            SizedBox(width: 8),
            Text('提示'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(height: 8),
            Text(
              '功能待实现',
              style: TextStyle(fontSize: 18),
            ),
            SizedBox(height: 8),
            Text(
              '该功能正在开发中',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
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
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
