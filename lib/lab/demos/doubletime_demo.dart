import 'package:flutter/material.dart';

import '../../core/doubletime/doubletime.dart';
import '../lab_container.dart';

class DoubleTimeDemo extends DemoPage {
  @override
  String get title => 'Double Time';

  @override
  String get description => '计划/实际双轴时间块，按 1 小时网格显示占用比例';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) {
    return const DoubleTimePage();
  }
}

void registerDoubleTimeDemo() {
  demoRegistry.register(DoubleTimeDemo());
}
