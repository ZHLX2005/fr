import 'package:flutter/material.dart';

import 'package:xiaodouzi_fr/screens/profile/profile_page.dart';
import 'package:xiaodouzi_fr/screens/chat/home_page.dart';
import 'package:xiaodouzi_fr/core/focus/focus_home_page.dart';
import 'package:xiaodouzi_fr/core/timetable/presentation/timetable_page.dart';
import '../fr_route_handler.dart';

/// fr://lab/core/{pageKey} → 4 个核心页之一
///
/// Router 阶段：authority 'lab/core/...' 前缀匹配到 'lab/core'。
/// Handler 从 authority 尾段切 pageKey：authority='lab/core/profile' → pageKey='profile'。
///
/// pageKey: profile | home | focus | timetable
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
      'focus' => const FocusHomePage(),
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
