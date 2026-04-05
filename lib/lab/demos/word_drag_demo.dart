import 'package:flutter/material.dart';
import '../lab_container.dart';
import '../../core/word_drag/word_drag.dart';

/// 弹性拖动背单词Demo
class WordDragDemo extends DemoPage {
  @override
  String get title => '单词拖拽';

  @override
  String get description => '弹性拖动效果的背单词交互';

  @override
  bool get preferFullScreen => false;

  @override
  Widget buildPage(BuildContext context) {
    return const WordDragPage();
  }
}

void registerWordDragDemo() {
  demoRegistry.register(WordDragDemo());
}
