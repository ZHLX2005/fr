// Schema 模块 - 内部链接协议
//
// 提供文本内嵌可点击链接功能，支持跳转到应用内 Demo 页面和核心页面
//
// 使用方式:
// ```dart
// import 'package:flutter_application_1/core/schema/schema.dart';
//
// // Demo 页面: [文字](fr://lab/demo/key)
// SchemaText('访问 [悬浮截屏](fr://lab/demo/悬浮截屏) 示例')
//
// // 核心页面: [文字](fr://lab/core/profile|home|focus|timetable)
// SchemaText('查看 [课表](fr://lab/core/timetable)')
//
// // 跳转到指定 schema
// await schemaNavigator.navigateToSchema('fr://lab/demo/悬浮截屏');
// ```

export 'schema_service.dart';
export 'schema_parser.dart';
export 'schema_text.dart';
export 'schema_navigator.dart';
