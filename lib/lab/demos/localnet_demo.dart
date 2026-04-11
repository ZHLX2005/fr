import 'package:flutter/material.dart';
import '../lab_container.dart';
import '../../core/localnet/pages/localnet_discover_page.dart';

/// LocalNet 局域网发现与聊天Demo
class LocalnetDemo extends DemoPage {
  @override
  String get title => 'LocalNet';

  @override
  String get description => '局域网设备发现与实时通讯';

  @override
  bool get preferFullScreen => false;

  @override
  Widget buildPage(BuildContext context) {
    return const LocalnetDiscoverPage();
  }
}

void registerLocalnetDemo() {
  demoRegistry.register(LocalnetDemo());
}
