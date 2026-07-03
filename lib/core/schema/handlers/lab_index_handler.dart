import 'package:flutter/material.dart';

import 'package:xiaodouzi_fr/screens/profile/lab/lab_page.dart';
import '../fr_route_handler.dart';

/// fr://lab → LabPage 首页
class LabIndexHandler extends FrRouteHandler {
  const LabIndexHandler();

  @override
  Widget build(BuildContext context, FrRouteMatch match) {
    return const LabPage();
  }
}