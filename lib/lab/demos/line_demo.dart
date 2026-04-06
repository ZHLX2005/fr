// Lab 入口文件 - 引用 core/line 模块
//
// 此文件仅作为 Lab 页面入口，实际逻辑在 core/line 中

import '../../core/line/line.dart';
import '../../lab/lab_container.dart';

void registerLineDemo() {
  demoRegistry.register(LineDemo());
}

class LineDemo extends DemoPage {
  @override
  String get title => '线';

  @override
  String get description => '线';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) {
    return const SongSelectPage();
  }
}
