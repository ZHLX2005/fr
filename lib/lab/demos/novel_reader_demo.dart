import 'package:flutter/material.dart';

import '../lab_container.dart';
import '../../core/novel_reader/novel_reader_constants.dart';
import '../../core/novel_reader/novel_reader_page.dart';

class NovelReaderDemo extends DemoPage {
  @override
  String get title => NovelReaderConstants.title;

  @override
  String get description => NovelReaderConstants.description;

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) {
    return const NovelReaderBookshelfPage();
  }
}

void registerNovelReaderDemo() {
  demoRegistry.register(NovelReaderDemo());
}
