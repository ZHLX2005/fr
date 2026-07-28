import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../lab_container.dart';
import 'clock/providers/lab_clock_provider.dart';
import 'clock/providers/lab_track_provider.dart';
import 'clock/widgets/clocks_tab.dart';
import 'clock/widgets/tracks_tab.dart';
import 'clock/widgets/dashboard_tab.dart';
import 'clock/widgets/zen_theme.dart';

class ClockDemo extends DemoPage {
  @override
  String get title => 'Clock';
  @override
  String get slug => 'clock';
  @override
  String get description => '时钟 · 编排 · 节拍';
  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LabClockProvider()..loadClocks()),
        ChangeNotifierProvider(create: (_) => LabTrackProvider()..loadTracks()),
      ],
      child: const _ClockShell(),
    );
  }
}

class _ClockShell extends StatefulWidget {
  const _ClockShell();
  @override
  State<_ClockShell> createState() => _ClockShellState();
}

class _ClockShellState extends State<_ClockShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: ZenColors.bg,
        canvasColor: ZenColors.bg,
        primaryColor: ZenColors.sage,
        splashColor: ZenColors.sage.withValues(alpha: 0.1),
        highlightColor: ZenColors.sage.withValues(alpha: 0.05),
        fontFamily:
            '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
      ),
      home: Scaffold(
        body: IndexedStack(
          index: _index,
          children: const [ClocksTab(), TracksTab(), DashboardTab()],
        ),
        bottomNavigationBar: NavigationBar(
          backgroundColor: ZenColors.surface,
          indicatorColor: ZenColors.sage.withValues(alpha: 0.15),
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.access_time_outlined), selectedIcon: Icon(Icons.access_time), label: 'Clocks'),
            NavigationDestination(icon: Icon(Icons.queue_music_outlined), selectedIcon: Icon(Icons.queue_music), label: 'Tracks'),
            NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          ],
        ),
      ),
    );
  }
}

void registerClockDemo() {
  demoRegistry.register(ClockDemo());
}
