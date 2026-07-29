import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../lab_container.dart';
import 'clock/providers/lab_clock_provider.dart';
import 'clock/providers/lab_track_provider.dart';
import 'clock/widgets/clocks_tab.dart';
import 'clock/widgets/tracks_tab.dart';
import 'clock/widgets/dashboard_tab.dart';
import 'clock/widgets/track_records_page.dart';
import 'package:xiaodouzi_fr/widgets/theme/zen_theme.dart';

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
  bool get timePage => true;

  @override
  Widget buildPage(BuildContext context) {
    // Reuse the global LabClockProvider that main.dart already registered
    // (it's needed at cold-start so the home-screen widget can sync before
    // the user opens this page). If we `create` a fresh one here we end up
    // with TWO providers writing to the same SharedPreferences from two
    // independent Timers — one overwrites the other, and any wipe done on
    // one is silently undone by the other on the next tick. LabTrackProvider
    // isn't wired at app root, so it's still created here.
    return ChangeNotifierProvider(
      create: (_) => LabTrackProvider()..loadTracks(),
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

  /// Cached during didChangeDependencies; used in dispose where `context`
  /// lookups are unsafe. LabClockProvider is the app-root singleton, so it
  /// outlives this page.
  LabClockProvider? _clockProvider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _clockProvider ??= Provider.of<LabClockProvider>(context, listen: false);
    // 页面进入：恢复应该响的 clock 节拍（如果用户之前退出时停了）。
    _clockProvider?.resumeActiveBeat();
  }

  @override
  void dispose() {
    // 页面退出：释放 beat。LabClockProvider 是 main 全局单例不会销毁，时间倒数
    // 继续正确（数据驱动），只是用户离开 Clock 页就不该再听到节拍声。
    // 用缓存的引用，不依赖 dispose 阶段的 context lookup（不安全且会被吞）。
    _clockProvider?.releaseAllBeats();
    super.dispose();
  }

  String get _title => const ['Clocks', 'Tracks', 'Dashboard'][_index];

  List<Widget> get _appBarActions {
    return [
      // 全局逃生舱：老用户如果 clock 数据卡死（无法添加/停止/删除），
      // 点这个按钮直接把 clock+track 的 SharedPreferences 全清了。
      // 所有 tab 都保留，因为卡死时 Clocks tab 本身可能都进不去。
      IconButton(
        tooltip: 'Wipe all clock data',
        icon: const Icon(Icons.delete_forever_outlined),
        onPressed: _confirmWipeAll,
      ),
      if (_index == 1)
        IconButton(
          tooltip: 'Track records',
          icon: const Icon(Icons.history),
          onPressed: () {
            // push 出来的新 route 不在 ClockDemo 的 ChangeNotifierProvider 树里，
            // 必须把当前的 LabTrackProvider 实例手动带进去，否则
            // TrackRecordsPage 里的 Consumer<LabTrackProvider> 会抛
            // ProviderNotFoundException → 白屏。
            final trackP = context.read<LabTrackProvider>();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChangeNotifierProvider<LabTrackProvider>.value(
                  value: trackP,
                  child: const TrackRecordsPage(),
                ),
              ),
            );
          },
        ),
    ];
  }

  Future<void> _confirmWipeAll() async {
    final clockP = context.read<LabClockProvider>();
    final trackP = context.read<LabTrackProvider>();
    final ok = await ZenConfirmDialog.show(
      context: context,
      title: 'Wipe all clock data?',
      message:
          '这会清空所有 clock、track、记录及节拍配置（包括旧版残留数据）。\n'
          '用于修复旧版本导致的卡死问题。\n\n'
          '此操作不可撤销。',
      confirmLabel: 'Wipe',
      onConfirm: () async {
        await clockP.wipeAllData();
        await trackP.wipeAllData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All clock data wiped.')),
          );
        }
      },
    );
    if (!ok || !mounted) return;
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