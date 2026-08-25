import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../lab_container.dart';
import 'calendar/data/lab_calendar_provider.dart';
import 'calendar/data/lab_people_provider.dart';
import 'calendar/ui/annual_report_page.dart';
import 'calendar/ui/day_detail_sheet.dart';
import 'calendar/ui/day_view.dart';
import 'calendar/ui/month_view.dart';
import 'calendar/ui/people_view.dart';
import 'calendar/ui/week_view.dart';
import 'calendar/ui/widgets/pill_segmented.dart';
import 'calendar/ui/year_view.dart';
import 'calendar/service/config/calendar_settings_page.dart';
import '../../core/theme/paper_palette.dart';
import '../../core/theme/typography.dart';

/// 日历待办 Demo（v2 进化版）
///
/// - 5 视图：今天 / 月 / 周 / 年 / 人 / 报表
/// - 支持农历 + 公历双轨生日
/// - 长按新建 / 点看 / 点编辑三态
class CalendarDemo extends DemoPage {
  @override
  String get title => '日历待办';

  @override
  String get slug => 'calendar';

  @override
  String get description => '人·农历·生日·五视图 日式极简';

  @override
  bool get preferFullScreen => true;

  @override
  bool get timePage => true;

  @override
  Widget buildPage(BuildContext context) {
    // MultiProvider 提到 CalendarDemo.buildPage() 顶层，让 push 出去的 route
    // （PersonFormSheet / EventFormSheet / PersonDetailPage）也能访问 provider。
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LabCalendarProvider()),
        ChangeNotifierProvider(create: (_) => LabPeopleProvider()),
      ],
      child: const _CalendarDemoPage(),
    );
  }
}

class _CalendarDemoPage extends StatefulWidget {
  const _CalendarDemoPage();

  @override
  State<_CalendarDemoPage> createState() => _CalendarDemoPageState();
}

class _CalendarDemoPageState extends State<_CalendarDemoPage> {
  static const _pillItems = ['今天', '月', '周', '年', '人', '报表'];
  int _index = 1; // 默认月视图
  late final PageController _page;

  @override
  void initState() {
    super.initState();
    _page = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _openDaySheet(DateTime date) {
    final cal = context.read<LabCalendarProvider>();
    final people = context.read<LabPeopleProvider>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DayDetailSheet(date: date, cal: cal, people: people),
    );
  }

  void _openInlineEvent(DateTime date) {
    final cal = context.read<LabCalendarProvider>();
    final people = context.read<LabPeopleProvider>();
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => DayDetailSheet(date: date, cal: cal, people: people),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // watch：provider 的 _init 完成（ready 置位）时 notifyListeners → 本 build 重建，
    // 从 loading 切到真实 PageView。
    final cal = context.watch<LabCalendarProvider>();
    final people = context.watch<LabPeopleProvider>();
    final pp = PaperPalette.of(context);
    return Scaffold(
      backgroundColor: pp.bg,
      appBar: AppBar(
        backgroundColor: pp.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.home_outlined),
          color: pp.ink,
          onPressed: () {
            cal.jumpToday();
            setState(() => _index = 1);
            _page.jumpToPage(1);
          },
        ),
        title: Text('日历待办', style: AppText.title()),
        actions: [
          Center(
            child: PillSegmented(
              items: _pillItems,
              selectedIndex: _index,
              onChanged: (i) {
                setState(() => _index = i);
                _page.jumpToPage(i);
              },
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: '日历设置（group / DSL）',
            onPressed: () {
              // 新 route 不在本页 MultiProvider 树内，必须把 provider 实例手动带进去，
              // 否则 CalendarSettingsPage 里的 Provider.of<LabCalendarProvider> 会抛
              // ProviderNotFoundException → 红屏崩溃。
              final calP = context.read<LabCalendarProvider>();
              final peopleP = context.read<LabPeopleProvider>();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MultiProvider(
                    providers: [
                      ChangeNotifierProvider<LabCalendarProvider>.value(
                        value: calP,
                      ),
                      ChangeNotifierProvider<LabPeopleProvider>.value(
                        value: peopleP,
                      ),
                    ],
                    child: const CalendarSettingsPage(),
                  ),
                  fullscreenDialog: true,
                ),
              );
            },
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: (!cal.ready || !people.ready)
          ? Center(
              child: CircularProgressIndicator(color: pp.inkMuted),
            )
          : PageView(
        controller: _page,
        onPageChanged: (i) => setState(() => _index = i),
        children: [
          DayView(cal: cal),
          MonthView(onDayTap: _openDaySheet, onDayLongPress: _openInlineEvent),
          WeekView(onDayTap: _openDaySheet),
          YearView(onMonthTap: (m) {
            cal.setView(cal.viewYear, m);
            setState(() => _index = 1);
            _page.jumpToPage(1);
          }),
          PeopleView(cal: cal, people: people),
          AnnualReportPage(cal: cal, people: people),
        ],
      ),
    );
  }
}

void registerCalendarDemo() {
  demoRegistry.register(CalendarDemo());
}