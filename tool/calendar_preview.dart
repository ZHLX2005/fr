import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xiaodouzi_fr/core/calendar/domain/calendar_task.dart';
import 'package:xiaodouzi_fr/core/calendar/presentation/calendar_page.dart';
import 'package:xiaodouzi_fr/core/calendar/presentation/calendar_view_mode.dart';
import 'package:xiaodouzi_fr/core/storage/hive/hive_calendar_store.dart';
import 'package:xiaodouzi_fr/core/storage/hive/hive_store.dart';

/// 本地视觉预览入口：`flutter run -t tool/calendar_preview.dart -d windows`
///
/// 让 Windows 也能跑真 Flutter 布局（无 Android 设备时做视觉验收用），
/// 不进入正式 App 的导航，也不参与业务包发布。
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HiveStore.instance.init();
  final store = await HiveCalendarStore.open();

  final requestedView = Uri.base.queryParameters['view'];
  final initialView = CalendarViewMode.values.firstWhere(
    (mode) => mode.name == requestedView,
    orElse: () => CalendarViewMode.list,
  );
  // 预览入口用 URL 参数切视图，避免靠坐标点菜单做视觉验收。
  await store.settings.write('calendar.viewMode', initialView.name);

  final today = DateTime.now();
  final existing = await store.calendar.tasksOnDay(today);
  if (existing.isEmpty) {
    await store.calendar.create(
      CalendarTaskDraft(
        title: '冥想 10 分钟',
        start: DateTime(today.year, today.month, today.day, 7, 30),
        end: DateTime(today.year, today.month, today.day, 7, 45),
      ),
    );
    await store.calendar.create(
      CalendarTaskDraft(
        title: '活动颈部',
        start: DateTime(today.year, today.month, today.day, 9, 0),
        end: DateTime(today.year, today.month, today.day, 9, 15),
      ),
    );
    await store.calendar.create(
      CalendarTaskDraft(
        title: '整理本周会议记录',
        notes: '把录音摘要归档到项目文档',
        start: DateTime(today.year, today.month, today.day, 14, 0),
        end: DateTime(today.year, today.month, today.day, 15, 0),
      ),
    );
    await store.calendar.create(
      CalendarTaskDraft(
        title: '晚间复盘',
        start: DateTime(today.year, today.month, today.day, 21, 30),
        end: DateTime(today.year, today.month, today.day, 22, 0),
      ),
    );
  }

  runApp(
    ProviderScope(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: const CalendarPage(),
      ),
    ),
  );
}
