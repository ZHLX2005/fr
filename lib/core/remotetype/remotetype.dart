// lib/core/remotetype/remotetype.dart
//
// 远程输入（RemoteType）barrel：外部（lab 注册壳等）从这里取入口，
// 内部实现按层拆分——data（常量/偏好）、protocol（会话/加密/同步管线）、
// ui（连接与打字）、canvas（横竖屏画布 + template/ 布局模板）。

export 'data/rt_constants.dart' show kRemoteTypeDemoSlug;
export 'rt_page.dart';
