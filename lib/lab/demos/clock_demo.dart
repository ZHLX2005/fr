import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../lab_container.dart';
import 'clock/providers/lab_clock_provider.dart';
import 'clock/providers/lab_track_provider.dart';
import 'clock/widgets/clocks_tab.dart';
import 'clock/widgets/tracks_tab.dart';
import 'clock/widgets/dashboard_tab.dart';
import 'clock/widgets/track_records_page.dart';
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

/// Single Scaffold/IndexedStack host. Each tab is a plain widget (no inner
/// Scaffold or FAB) so hit-testing works correctly when the user switches
/// between tabs. The shell owns the AppBar (with tab-specific actions), the
/// FAB (delegated to the active tab), and the bottom NavigationBar.
class _ClockShell extends StatefulWidget {
  const _ClockShell();
  @override
  State<_ClockShell> createState() => _ClockShellState();
}

class _ClockShellState extends State<_ClockShell> {
  int _index = 0;

  // Tab-level callbacks (set by each tab via context.findAncestorStateOfType
  // pattern below). null when the tab hasn't provided one yet.
  Future<void> Function(BuildContext)? _clocksOpenEditor;
  Future<void> Function(BuildContext)? _tracksOpenEditor;

  String get _title => const ['Clocks', 'Tracks', 'Dashboard'][_index];

  List<Widget>? get _appBarActions {
    if (_index != 1) return null; // Only Tracks shows the records icon.
    return [
      IconButton(
        tooltip: 'Track records',
        icon: const Icon(Icons.history),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TrackRecordsPage()),
        ),
      ),
    ];
  }

  void _onFabPressed() {
    final cb = _index == 0
        ? _clocksOpenEditor
        : _index == 1
            ? _tracksOpenEditor
            : null;
    if (cb != null) cb(context);
  }

  @override
  Widget build(BuildContext context) {
    final showFab = _index != 2; // No FAB on Dashboard.
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
        backgroundColor: ZenColors.bg,
        appBar: AppBar(
          backgroundColor: ZenColors.bg,
          elevation: 0,
          title: Text(_title, style: ZenText.title),
          actions: _appBarActions,
        ),
        body: IndexedStack(
          index: _index,
          children: [
            ClocksTab(
              onReady: (openEditor) => _clocksOpenEditor = openEditor,
            ),
            TracksTab(
              onReady: (openEditor) => _tracksOpenEditor = openEditor,
            ),
            const DashboardTab(),
          ],
        ),
        floatingActionButton: showFab
            ? FloatingActionButton(
                onPressed: _onFabPressed,
                backgroundColor: ZenColors.sage,
                child: const Icon(Icons.add, color: Colors.white),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          backgroundColor: ZenColors.surface,
          indicatorColor: ZenColors.sage.withValues(alpha: 0.15),
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.access_time_outlined),
              selectedIcon: Icon(Icons.access_time),
              label: 'Clocks',
            ),
            NavigationDestination(
              icon: Icon(Icons.queue_music_outlined),
              selectedIcon: Icon(Icons.queue_music),
              label: 'Tracks',
            ),
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
          ],
        ),
      ),
    );
  }
}

void registerClockDemo() {
  demoRegistry.register(ClockDemo());
}