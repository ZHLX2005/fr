// Schema 模块 - fr:// 内部 URL 路由中心
//
// 使用方式:
// ```dart
// import 'package:xiaodouzi_fr/core/schema/schema.dart';
//
// // 注册路由（main 启动时）
// registerAllFrRoutes();
//
// // 文本中嵌入可点击链接
// SchemaText('访问 [悬浮截屏](fr://lab/demo/clock) 示例')
//
// // 内部代码跳转
// await frRouter.handle(context, 'fr://lab/demo/clock');
//
// // MethodChannel 反注册（main.dart）
// await FrNavigator.handle(context, 'fr://notion/image-host?autocapture=true');
// ```

export 'fr_uri.dart';
export 'fr_route.dart';
export 'fr_route_handler.dart';
export 'fr_router.dart';
export 'fr_navigator.dart';
export 'schema_text.dart';
export 'bootstrap_routes.dart';
