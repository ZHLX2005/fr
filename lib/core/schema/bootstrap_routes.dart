import 'fr_router.dart';
import 'fr_route.dart';
import 'handlers/lab_index_handler.dart';
import 'handlers/lab_demo_handler.dart';
import 'handlers/lab_core_handler.dart';
import 'handlers/notion_image_host_handler.dart';
import 'handlers/notion_create_page_handler.dart';
import 'handlers/timetable_handler.dart';

/// 集中注册所有 fr:// 路由
///
/// 在 main() bootstrapLab() 之后调一次。
///
/// 注册顺序：长 prefix 在前（'lab/demo' 先于 'lab'）— FrRouter.findHandler
/// 用最长 prefix 命中，所以顺序不强制，但语义上 'lab/demo' 和 'lab/core'
/// 是 'lab' 的子域，按子域在前更直观。
void registerAllFrRoutes() {
  frRouter.registerAll([
    FrRoute('lab', handler: const LabIndexHandler()),
    FrRoute('lab/demo', handler: const LabDemoHandler()),
    FrRoute('lab/core', handler: const LabCoreHandler()),
    FrRoute('notion/image-host', handler: const NotionImageHostHandler()),
    FrRoute('notion/create-page', handler: const NotionCreatePageHandler()),
    FrRoute('timetable', handler: const TimetableHandler()),
  ]);
}
