/// Lab 模块引导文件
/// 集中注册所有 Demo 页面
library lab_bootstrap;

import '../core/schema/schema.dart' show initSchemaRegistry;
import 'demos/grid_dashboard_demo.dart';
import 'demos/notebook_demo_ai_proto.dart';
import 'demos/clock_demo.dart';
import 'demos/network_demo.dart';
import 'demos/network_env_demo.dart';
import 'demos/game_2048_demo.dart';
import 'demos/free_canvas_demo.dart';
import 'demos/drag_reorder_demo.dart';
import 'demos/web_bookmark_demo.dart';
import 'demos/storage_analyze_demo.dart';
import 'demos/hexagon_panel_demo.dart';
import 'demos/typewriter_demo.dart';
import 'demos/snake_game_demo.dart';
import 'demos/api_test_demo.dart';
import 'demos/calendar_demo.dart';
import 'demos/my_diary_header_demo.dart';
import 'demos/water_capsule_demo.dart';
import 'demos/speech_synthesis_demo.dart';
import 'demos/line_demo.dart';
import 'demos/torch_demo.dart';
import 'demos/sensor_demo.dart';
import 'demos/word_drag_demo.dart';
import 'demos/overlay_demo.dart';
import 'demos/body_map_demo.dart';
import 'demos/localnet_demo.dart';
import 'demos/gallery_demo.dart';
import 'demos/schema_demo.dart';
import 'demos/color_palette_demo.dart';

/// 注册所有 Demo 页面
void registerAllDemos() {
  registerGridDashboardDemo();
  registerNotebookDemoAiProto();
  registerClockDemo();
  registerNetworkDemo();
  registerNetworkEnvDemo();
  registerGame2048Demo();
  registerFreeCanvasDemo();
  registerDragReorderDemo();
  registerWebBookmarkDemo();
  registerStorageAnalyzeDemo();
  registerHexagonPanelDemo();
  registerTypewriterDemo();
  registerSnakeGameDemo();
  registerApiTestDemo();
  registerCalendarDemo();
  registerMyDiaryHeaderDemo();
  registerWaterCapsuleDemo();
  registerSpeechSynthesisDemo();
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
}

/// 初始化 Schema 注册表
void bootstrapLab() {
  registerAllDemos();
  initSchemaRegistry();
}
