/// nx-nx 的响应形状。
///
/// nx-nx 是**扁平信封**（`{status, templates, errors, count}`），
/// 没有 goframe 那层 `{ok, data}` —— 所以这里如实按它自己的形状解析，
/// 不替它套别的后端惯用的信封。
library;

/// nx-nx 的一个模板（`GET /api/templates` 的一项）。
class NxNxTemplate {
  /// 模板 id（也是 `GET /api/templates/:id` 的路径参数）。
  final String id;

  /// 模板名。
  final String name;

  /// 一句话说明。
  final String description;

  const NxNxTemplate({
    required this.id,
    required this.name,
    required this.description,
  });

  factory NxNxTemplate.fromJson(Map<String, dynamic> json) => NxNxTemplate(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? json['id'] ?? ''}',
        description: '${json['description'] ?? ''}',
      );
}

/// `GET /api/templates` 的响应。
class NxNxTemplateList {
  final List<NxNxTemplate> templates;

  /// 不合法的模板（列不出来，但要在界面上说出来 —— 静默吞掉会让人以为没有）。
  final List<String> errors;

  const NxNxTemplateList({this.templates = const [], this.errors = const []});

  factory NxNxTemplateList.fromJson(Map<String, dynamic> json) {
    // nx-nx 走 goframe 的信封（`{ok, data}`），但别把它写死 ——
    // 解一层 `data`（有就解），没有就当它本来就是平的。
    final body = (json['data'] is Map<String, dynamic>)
        ? json['data'] as Map<String, dynamic>
        : json;
    final raw = body['templates'];
    final templates = <NxNxTemplate>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map<String, dynamic>) templates.add(NxNxTemplate.fromJson(e));
      }
    }
    final rawErrors = body['errors'];
    final errors = <String>[];
    if (rawErrors is List) {
      for (final e in rawErrors) {
        if (e is Map) {
          final id = '${e['id'] ?? ''}';
          final msg = '${e['message'] ?? ''}';
          errors.add(id.isEmpty ? msg : '$id: $msg');
        } else {
          errors.add('$e');
        }
      }
    }
    return NxNxTemplateList(templates: templates, errors: errors);
  }
}
