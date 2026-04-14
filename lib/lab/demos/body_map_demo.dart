import 'package:flutter/material.dart';
import '../../core/body/body.dart';
import '../lab_container.dart';

/// 身体感受记录Demo
class BodyMapDemo extends DemoPage {
  @override
  String get title => '身体记录';

  @override
  String get description => '色块人体图 + 点击热区 + 感受记录';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) {
    return BodyMapPage(title: '全身', regions: fullBodyRegions);
  }
}

/// 注册身体记录Demo
void registerBodyMapDemo() {
  demoRegistry.register(BodyMapDemo());
}
