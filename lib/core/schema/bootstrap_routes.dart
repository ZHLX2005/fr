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