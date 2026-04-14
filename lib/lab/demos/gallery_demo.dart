import 'package:flutter/material.dart';
import '../lab_container.dart';
import '../../screens/gallery/gallery_manage_page.dart';

/// 图库管理Demo
class GalleryDemo extends DemoPage {
  @override
  String get title => '图库管理';

  @override
  String get description => '系统图片管理与相册分组';

  
@override
  bool get preferFullScreen => true;


  @override
  Widget buildPage(BuildContext context) {
    return const GalleryManagePage();
  }
}

void registerGalleryDemo() {
  demoRegistry.register(GalleryDemo());
}
