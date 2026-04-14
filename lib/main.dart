import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart' as classic_provider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/providers.dart';
import 'screens/home/home_page.dart';
import 'lab/lab_bootstrap.dart';
import 'screens/profile/profile_page.dart';
import 'screens/lab/lab_page.dart';
import 'core/focus/focus_home_page.dart';
import 'core/focus/providers/focus_provider.dart';
import 'core/timetable/timetable.dart';
import 'widgets/xiaodouzi_bottom_bar.dart';
import 'core/schema/schema.dart';
import 'lab/providers/lab_note_provider.dart';
import 'lab/providers/lab_clock_provider.dart';
import 'providers/agent_chat_provider.dart';
import 'core/body/models/body_record_repo.dart';

void main() async {
  // 确保 Flutter 绑定初始化
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 Hive
  final hiveRepo = HiveTimetableRepository();
  await hiveRepo.init();
  await bodyRecordRepo.init();

  // 初始化 Lab 模块（注册所有 Demo + Schema）
  bootstrapLab();

  // 使用 ProviderScope 包装应用，注入 Repository
  runApp(
    ProviderScope(
      overrides: [TimetableStore.repoProvider.overrideWithValue(hiveRepo)],
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
  Widget build(BuildContext context) {
    return classic_provider.MultiProvider(
      providers: [
        classic_provider.ChangeNotifierProvider.value(value: _themeProvider),
        classic_provider.ChangeNotifierProvider(
          create: (_) => MessageProvider(),
        ),
        classic_provider.ChangeNotifierProvider(
          create: (_) => LabNoteProvider(),
        ),
        classic_provider.ChangeNotifierProvider(
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
    _PlaceholderPage(icon: Icons.wifi, title: 'LocalNet', desc: '局域网发现功能开发中'),
    _PlaceholderPage(icon: Icons.photo_library, title: '图库', desc: '图库管理功能开发中'),
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

/// 占位页面 - 功能开发中
class _PlaceholderPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;

  const _PlaceholderPage({
    required this.icon,
    required this.title,
    required this.desc,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 80, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 24),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              desc,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
