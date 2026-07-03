import 'package:flutter/material.dart';

import 'package:xiaodouzi_fr/screens/profile/lab/lab_page.dart';
import '../fr_route_handler.dart';

/// fr://lab → LabPage 首页
///
/// Router 阶段：authority == 'lab' 直接命中。
/// 防御性 guard：match.authority 必须严格等于 'lab'，不能误匹配 'lab/demo' / 'lab/core'。
class LabIndexHandler extends FrRouteHandler {
  const LabIndexHandler();

  @override
  Widget build(BuildContext context, FrRouteMatch match) {
    assert(
      match.authority == 'lab',
      'LabIndexHandler 期望 authority=lab，实际: ${match.authority}',
    );
    return const LabPage();
  }
}
