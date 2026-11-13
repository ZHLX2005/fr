/// 新建项目面板的「表单模型」：把模板的 option schema 翻译成三件事——
///
///   1. 必填 / 可选两组的渲染顺序
///   2. 当前填写够不够格生成（决定「预览文件」「生成项目」两个按钮的可点性）
///   3. 输出目录的默认建议名
///
/// ## 为什么面板不认识任何具体的选项名
///
/// 曾经把可点性硬编码在 `letters` 上 —— 那是 server-cli-web 家族的专属字段。
/// mono-gf 的必填项是 `name`、std-a-lang 是 `lang`，两个模板怎么填都够不到
/// 那条分支，按钮恒灰、点了没反应、界面上也看不出差什么。
/// 改成完全由 **schema 驱动**后，模板换必填项、加选项，面板不必跟着改。
///
/// 这份规则是服务端 `resolveVars` 的**镜像**，两边必须逐条对齐 ——
/// 面板判定「够了」，服务端也得认。
library;

import '../../../../api/mnws/nxnx/nxnx_models.dart';

/// 选项值表（按选项名索引）。
typedef NxNxOptionValues = Map<String, dynamic>;

/// 一个挡住生成的原因。
class NxNxOptionIssue {
  /// `missing` = 没填；`invalid` = 填了但格式不对。
  final String kind;
  final String name;
  final String label;
  final String message;

  const NxNxOptionIssue({
    required this.kind,
    required this.name,
    required this.label,
    required this.message,
  });

  bool get isMissing => kind == 'missing';
}

/// 目录名候选。超过这个形态的值（如 std-a-lang 的「ts, go」）不参与推导。
final RegExp _slug = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$');

/// 什么算「没填」。
///
/// 空串 / null 不算；**0 与 false 算** —— 它们是合法取值。
bool nxNxIsBlank(Object? value) =>
    value == null || value == '' || (value is String && value.isEmpty);

/// 有默认值就不算缺：服务端 blank + default 会落回默认值。
bool _hasValue(NxNxOption opt, NxNxOptionValues values) =>
    !nxNxIsBlank(values[opt.name]) ||
    (opt.defaultValue != null && opt.defaultValue != '');

/// 选项的显示名（没写 label 就用名字）。
String nxNxOptionLabel(NxNxOption opt) =>
    opt.label.isNotEmpty ? opt.label : opt.name;

/// 必填在前、可选在后；组内保持模板声明的顺序。
({List<NxNxOption> required, List<NxNxOption> optional}) nxNxSplitOptions(
  List<NxNxOption> opts,
) {
  return (
    required: opts.where((o) => o.required).toList(),
    optional: opts.where((o) => !o.required).toList(),
  );
}

/// 单项**格式**校验，留空一律放行。
///
/// 「必填」和「格式」分开判（后者只管非空值），否则刚打开面板时满屏红字 ——
/// 还没动手就被告知错了。两类问题在 [nxNxBlockingIssues] 里汇合。
String? nxNxValidateOption(NxNxOption opt, Object? value) {
  if (nxNxIsBlank(value)) return null;
  final label = nxNxOptionLabel(opt);
  final type = opt.type.isEmpty ? 'string' : opt.type;

  if (type == 'number') {
    final n = double.tryParse('$value');
    return n == null ? '$label 必须是数字' : null;
  }
  if (type == 'letters') {
    return RegExp(r'^[a-z]{1,5}$', caseSensitive: false)
            .hasMatch('$value'.trim())
        ? null
        : '$label 必须是 1~5 位小写字母';
  }
  if (type == 'enum') {
    return opt.values.contains('$value')
        ? null
        : '$label 只能是 ${opt.values.join(' | ')}';
  }
  final pattern = opt.pattern;
  if (pattern != null && pattern.isNotEmpty) {
    try {
      return RegExp(pattern).hasMatch('$value')
          ? null
          : '$label 格式不符合要求';
    } catch (_) {
      // 模板写了个坏正则 —— 那就不拦（服务端也会报错，但别在界面上重复拦一次）
      return null;
    }
  }
  return null;
}

/// 当前填写挡住生成的全部原因：缺必填 + 格式非法。
///
/// 面板用它决定按钮可点性，并把原因原样显示出来 ——
/// **灰着的按钮必须说清自己在等什么**，否则用户只能干瞪眼。
List<NxNxOptionIssue> nxNxBlockingIssues(
  List<NxNxOption> opts,
  NxNxOptionValues values,
) {
  final issues = <NxNxOptionIssue>[];
  for (final opt in opts) {
    final label = nxNxOptionLabel(opt);
    if (opt.required && !_hasValue(opt, values)) {
      issues.add(NxNxOptionIssue(
        kind: 'missing',
        name: opt.name,
        label: label,
        message: '$label 必填',
      ));
      continue;
    }
    final err = nxNxValidateOption(opt, values[opt.name]);
    if (err != null) {
      issues.add(NxNxOptionIssue(
        kind: 'invalid',
        name: opt.name,
        label: label,
        message: err,
      ));
    }
  }
  return issues;
}

/// 一行说明「现在为什么点不了」；没有阻塞项时返回空串。
String nxNxDescribeIssues(List<NxNxOptionIssue> issues) {
  final missing = issues.where((i) => i.isMissing).map((i) => i.label).toList();
  final invalid = issues.where((i) => !i.isMissing).map((i) => i.message).toList();
  final parts = <String>[];
  if (missing.isNotEmpty) parts.add('还差必填项：${missing.join('、')}');
  if (invalid.isNotEmpty) parts.add(invalid.join('；'));
  return parts.join('　');
}

/// 由 schema 推项目名，用于输出目录的默认值与右侧预览标题。
///
/// 派生顺序与服务端对齐：
///   1. `letters` / `name` 选项有值就用
///   2. 否则取第一个必填选项的值，配上 namePrefix —— std-a-lang：lang=ts → a_ts
///   3. 推不出就返回空串，由用户自己填目录；**宁可空着也不猜错**。
String nxNxSuggestProjectName(NxNxTemplate? meta, NxNxOptionValues values) {
  if (meta == null) return '';
  final opts = meta.options;
  final primary = opts.where((o) => o.required).firstOrNull;
  final src = _slugOrEmpty(values['letters']) ??
      _slugOrEmpty(values['name']) ??
      (primary == null ? null : _slugOrEmpty(values[primary.name]));
  if (src == null || src.isEmpty) return '';
  final prefixRaw = values['prefix'];
  final prefix = (prefixRaw == null)
      ? meta.namePrefix
      : '$prefixRaw';
  return '$prefix$src';
}

String? _slugOrEmpty(Object? value) {
  final s = '${value ?? ''}'.trim();
  return _slug.hasMatch(s) ? s : null;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
