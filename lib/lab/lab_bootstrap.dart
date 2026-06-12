// Lab 模块引导文件
// 集中注册所有 Demo 页面

import '../core/schema/schema.dart' show initSchemaRegistry;
import 'demos/api_test_demo.dart';
import 'demos/body_map_demo.dart';
import 'demos/calendar_demo.dart';
import 'demos/clock_demo.dart';
import 'demos/crash_log_demo.dart';
import 'demos/color_palette_demo.dart';
import 'demos/demo_laboratory_demo.dart';
import 'demos/doubletime_demo.dart';
import 'demos/free_canvas_demo.dart';
import 'demos/gallery_demo.dart';
import 'demos/game_2048_demo.dart';
import 'demos/github_demo.dart';
import 'demos/grid_dashboard_demo.dart';
import 'demos/line_demo.dart';
import 'demos/localnet_demo.dart';
import 'demos/network_demo.dart';
import 'demos/novel_reader_demo.dart';
import 'demos/overlay_demo.dart';
import 'demos/pigment_palette_demo.dart';
import 'demos/qr_demo.dart';
import 'demos/schema_demo.dart';
import 'demos/sensor_demo.dart';
import 'demos/snake_game_demo.dart';
import 'demos/storage_analyze_demo.dart';
import 'demos/torch_demo.dart';
import 'demos/volume_decay_demo.dart';
import 'demos/web_bookmark_demo.dart';
import 'demos/word_drag_demo.dart';
import 'demos/rive_pendulum_demo.dart';
import 'demos/rive_data_bind_demo.dart';
import 'demos/block_editor_demo.dart';
import 'demos/bottom_bar_demo.dart';
import 'demos/set_tracker_demo.dart';
import 'demos/surround_game_demo.dart';

// 注册所有 Demo 页面
void registerAllDemos() {
  registerGridDashboardDemo();
  registerClockDemo();
  registerCalendarDemo();
  registerCrashLogDemo();
  registerNetworkDemo();
  registerGame2048Demo();
  registerFreeCanvasDemo();
  registerStorageAnalyzeDemo();
  registerSnakeGameDemo();
  registerApiTestDemo();
  registerLineDemo();
  registerTorchDemo();
  registerSensorDemo();
  registerWordDragDemo();
  registerOverlayDemo();
  registerBodyMapDemo();
  registerLocalnetDemo();
  registerGalleryDemo();
  registerSchemaDemo();
  registerColorPaletteDemo();
  registerGithubDemo();
  registerQrDemo();
  registerWebBookmarkDemo();
  registerDoubleTimeDemo();
  registerNovelReaderDemo();
  registerVolumeDecayDemo();
  registerDemoLaboratoryDemo();
  registerRivePendulumDemo();
  registerRiveDataBindDemo();
  registerBlockEditorDemo();
  registerPigmentPaletteDemo();
  registerSetTrackerDemo();
  registerBottomBarDemo();
  registerSurroundGameDemo();
}

// 初始化 Schema 注册表
void bootstrapLab() {
  registerAllDemos();
  initSchemaRegistry();
}
