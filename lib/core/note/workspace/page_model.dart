import '../blocks/block_editor_controller.dart';

/// 页面模型
///
/// Page 不是 Block，它是 BlockTree 的容器。
/// 磁盘上每个 Page = 一个 JSON 文件，文件里装的是一棵 Block 树。
class PageModel {
  final String id;
  String title;
  final BlockEditorController controller;
  final DateTime createdAt;
  DateTime updatedAt;

  PageModel({
    required this.id,
    required this.title,
    required this.controller,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();
}
