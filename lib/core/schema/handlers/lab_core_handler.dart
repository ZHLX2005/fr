import 'package:flutter/material.dart';

import 'package:xiaodouzi_fr/core/focus/focus_timer_page.dart';
import 'package:xiaodouzi_fr/core/timetable/presentation/timetable_page.dart';
import '../../../screens/containers/profile_container.dart';
import '../../../screens/containers/ai_container.dart';
import '../fr_route_handler.dart';

/// fr://lab/core/{pageKey} → 核心页直连
///
/// Router 阶段：authority 'lab/core/...' 前缀匹配到 'lab/core'。
/// Handler 从 authority 尾段切 pageKey：authority='lab/core/profile' → pageKey='profile'。
///
/// pageKey: profile | home | focus | timetable
/// （fr 33：Time 核心容器退役；focus 直达番茄钟计时页，timetable 直达课表，
/// 两者在 Lab 里另有 demo 入口 fr://lab/demo/{focus|timetable}。）
class LabCoreHandler extends FrRouteHandler {
  static const _prefix = 'lab/core/';

  const LabCoreHandler();

  @override
  Widget build(BuildContext context, FrRouteMatch match) {
    final auth = match.authority;
    if (!auth.startsWith(_prefix) || auth == _prefix.substring(0, _prefix.length - 1)) {
      return _UnknownCorePage(pageKey: auth);
    }
    final pageKey = auth.substring(_prefix.length);
    final Widget? page = switch (pageKey) {
      'profile' => const ProfilePage(),
      'home' => const HomePage(),
      'focus' => const FocusTimerPage(),
      'timetable' => const TimetablePage(),
      _ => null,
    };
    if (page == null) {
      return _UnknownCorePage(pageKey: pageKey);
    }
    return page;
  }
}

class _UnknownCorePage extends StatelessWidget {
  final String pageKey;
  const _UnknownCorePage({required this.pageKey});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('未知页面')),
      body: Center(child: Text('未知核心页面: $pageKey')),
    );
  }
}
