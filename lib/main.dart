import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/providers.dart';
import 'screens/home/home_page.dart';
import 'screens/friends/friends_page.dart';
import 'screens/profile/profile_page.dart';
import 'screens/lab/lab_page.dart';
import 'lab/lab_container.dart';
import 'lab/demos/grid_dashboard_demo.dart';
import 'lab/demos/notebook_demo.dart';
import 'lab/demos/clock_demo.dart';
import 'lab/demos/network_demo.dart';
import 'lab/demos/game_2048_demo.dart';
import 'lab/demos/canvas_demo.dart';
import 'lab/demos/drag_reorder_demo.dart';
import 'lab/demos/web_preview_demo.dart';
import 'lab/demos/flame_game_demo.dart';
import 'lab/providers/lab_note_provider.dart';
import 'lab/providers/lab_clock_provider.dart';

void main() {
  // 注册 Demo 页面
  registerGridDashboardDemo();
  registerNotebookDemo();
  registerClockDemo();
  registerNetworkDemo();
  registerGame2048Demo();
  registerCanvasDemo();
  registerDragReorderDemo();
  registerWebPreviewDemo();
  registerFlameGameDemo();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => MessageProvider()),
        ChangeNotifierProvider(create: (_) => FriendProvider()),
        ChangeNotifierProvider(create: (_) => LabNoteProvider()),
        ChangeNotifierProvider(create: (_) => LabClockProvider()),
        ChangeNotifierProxyProvider<UserProvider, ChatSessionProvider>(
          create: (_) => ChatSessionProvider(),
          update: (_, userProvider, sessionProvider) {
            sessionProvider!.init(userProvider.currentUser?.id ?? '');
            return sessionProvider;
          },
        ),
      ],
      child: MaterialApp(
        title: 'Flutter 聊天应用',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const MainScreen(),
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
    HomePage(),
    FriendsPage(),
    ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    final userProvider = context.read<UserProvider>();
    final friendProvider = context.read<FriendProvider>();

    await userProvider.init();
    await friendProvider.init();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        children: _pages,
      ),
      bottomNavigationBar: Consumer<ChatSessionProvider>(
        builder: (context, sessionProvider, child) {
          final unreadCount = sessionProvider.totalUnreadCount;

          return NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _onItemTapped,
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.chat_bubble_outline),
                selectedIcon: const Icon(Icons.chat_bubble),
                label: '聊天',
              ),
              NavigationDestination(
                icon: const Icon(Icons.people_outline),
                selectedIcon: const Icon(Icons.people),
                label: '通讯录',
              ),
              NavigationDestination(
                icon: const Icon(Icons.person_outline),
                selectedIcon: const Icon(Icons.person),
                label: '我的',
              ),
            ],
          );
        },
      ),
    );
  }
}
