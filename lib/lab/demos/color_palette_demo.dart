import 'package:flutter/material.dart';
import '../lab_container.dart';
import '../../core/color/color.dart';

/// 撞色色卡 Demo
class ColorPaletteDemo extends DemoPage {
  @override
  String get title => '撞色色卡';

  @override
  String get description => '两两一组展示配色方案，左右滑切换沉浸全屏';

  @override
  Widget buildPage(BuildContext context) {
    return const ColorPalettePage();
  }
}

void registerColorPaletteDemo() {
  demoRegistry.register(ColorPaletteDemo());
}
