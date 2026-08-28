// Lab 模块引导文件
// 集中注册所有 Demo 页面

import 'demos/api_test_demo.dart';
import 'demos/body_map_demo.dart';
import 'demos/calendar_demo.dart';
import 'demos/clock_demo.dart';
import 'demos/crash_log_demo.dart';
// demo_laboratory_demo 已并入 rive_demo（统一 Rive 演示）
import 'demos/rive_demo/rive_demo.dart' show registerRiveDemo;
import 'demos/doubletime_demo.dart';
import 'demos/gallery_demo.dart';
import 'demos/game_2048_demo.dart';
import 'demos/github_demo.dart';
import 'demos/line_demo.dart';
import 'demos/message_net_demo.dart';
import 'demos/network_demo.dart';
import 'demos/novel_reader_demo.dart';
import 'demos/notion_image_host_demo.dart';
import 'demos/overlay_demo.dart';
import 'demos/pigment_palette_demo.dart';
import 'demos/price_compare_demo.dart';
import 'demos/schema_demo.dart';
import 'demos/sensor_demo.dart';
import 'demos/snake_game_demo.dart';
import 'demos/storage_analyze_demo.dart';
import 'demos/torch_demo.dart';
import 'demos/volume_decay_demo.dart';
import 'demos/web_bookmark_demo.dart';
import 'demos/word_drag_demo.dart';
import 'demos/block_editor_demo.dart';
import 'demos/bottom_bar_demo.dart';
import 'demos/surround_game_demo.dart';
import 'demos/surround_game_lua_demo.dart';
import 'demos/reversi_demo.dart' show registerReversiLuaDemo;
import 'demos/jungle_chess_demo.dart';
import 'demos/kvcli_todo_demo.dart' show registerKvcliTodoDemo;
import 'demos/reaction_test_demo.dart';
import 'demos/metronome_demo.dart';
import 'demos/team_card_lua_demo.dart' show registerTeamCardLuaDemo;
import 'demos/surround_game_lua_demo.dart' show registerSurroundGameLuaDemo;
import 'demos/gomoku_lua_demo.dart' show registerGomokuLuaDemo;
import 'demos/jungle_chess_lua_demo.dart' show registerJungleChessLuaDemo;
import 'demos/go_lua_demo.dart' show registerGoLuaDemo;
import 'demos/tetris_lua_demo.dart' show registerTetrisLuaDemo;
import 'demos/coup_lua_demo.dart' show registerCoupLuaDemo;
import 'demos/recorder_demo.dart' show registerRecorderDemo;
import 'demos/relation_calc_demo.dart' show registerRelationCalcDemo;

// 注册所有 Demo 页面
void registerAllDemos() {
  registerClockDemo();
  registerCalendarDemo();
  registerCrashLogDemo();
  registerNetworkDemo();
  registerGame2048Demo();
  registerStorageAnalyzeDemo();
  registerSnakeGameDemo();
  registerApiTestDemo();
  registerLineDemo();
  registerTorchDemo();
  registerSensorDemo();
  registerWordDragDemo();
  registerOverlayDemo();
  registerBodyMapDemo();
  registerMessageNetDemo();
  registerGalleryDemo();
  registerSchemaDemo();
    registerGithubDemo();
  registerWebBookmarkDemo();
  registerDoubleTimeDemo();
  registerNovelReaderDemo();
  registerVolumeDecayDemo();
  registerRiveDemo();
  registerBlockEditorDemo();
  registerPigmentPaletteDemo();
  registerPriceCompareDemo();
  registerBottomBarDemo();
  registerSurroundGameDemo();
  registerReversiLuaDemo();
  registerJungleChessDemo();
  registerKvcliTodoDemo();
  registerNotionImageHostDemo();
  registerReactionTestDemo();
  registerMetronomeDemo();
  registerTeamCardLuaDemo();
  registerSurroundGameLuaDemo();
  registerGomokuLuaDemo();
  registerGoLuaDemo();
  registerJungleChessLuaDemo();
  registerTetrisLuaDemo();
  registerCoupLuaDemo();
  registerRecorderDemo();
  registerRelationCalcDemo();
}

// 初始化 Lab 模块
void bootstrapLab() {
  registerAllDemos();
}
