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
    final cal = context.read<LabCalendarProvider>();
    final people = context.read<LabPeopleProvider>();
    return Scaffold(
      backgroundColor: PaperPalette.bg,
      appBar: AppBar(
        backgroundColor: PaperPalette.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.home_outlined),
          color: PaperPalette.ink,
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
        ],
      ),
      body: PageView(
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