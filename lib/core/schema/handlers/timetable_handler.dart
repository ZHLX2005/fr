import 'package:flutter/material.dart';

import 'package:xiaodouzi_fr/core/timetable/presentation/timetable_page.dart';
import '../fr_route_handler.dart';

/// fr://timetable → 课表页
///
/// Router 阶段：authority 'timetable' 整段匹配。
/// 桌面 widget MethodChannel 'navigateToTimetable' 翻译成 fr://timetable
class TimetableHandler extends FrRouteHandler {
  const TimetableHandler();

  @override
  Widget build(BuildContext context, FrRouteMatch match) {
    assert(
      match.authority == 'timetable',
      'TimetableHandler 期望 authority=timetable，实际: ${match.authority}',
    );
    return const TimetablePage();
  }
}
