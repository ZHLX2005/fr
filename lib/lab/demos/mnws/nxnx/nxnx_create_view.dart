import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../api/mnws/mnws.dart';
import '../../../../api/mnws/nxnx/nxnx_models.dart';
import '../../../../core/ui/global/button/main.dart';
import '../../../../core/ui/global/nav/main.dart';
import '../../../../design_tokens/radius.dart';
import '../../../../design_tokens/spacing.dart';
import '../mnws_app_views.dart';
import 'nxnx_option_form.dart';
import 'nxnx_cli_hints.dart';
import 'nxnx_page.dart';
import 'nxnx_widgets.dart';

/// 新建项目：左侧选模板 → 中间按 schema 自动生成表单 → 右侧预览。
///
/// ## 设计要点
///
/// 这里**不猜**任何字段含义，表单完全由模板的 option schema 驱动：
/// 模板加一个选项，面板自动多一个控件，不需要改这个文件。
///
/// 面板也**不认识任何具体的选项名** —— 必填与否、能不能点「生成项目」、
/// 输出目录叫什么，全部由 schema + [nxNxBlockingIssues] 的同一套规则推出。
///
/// 视觉是**无色块 + 边框强调**：块靠描边分开，状态靠描边强弱区分。
class NxNxCreateView extends ConsumerStatefulWidget {
  final MnWsAppTarget target;

  /// 命令表（bootstrap 下发的）—— 底下那行 CLI 等价提示由它派生。
  final List<NxNxCommand> commands;

  const NxNxCreateView({
    super.key,
    required this.target,
    this.commands = const [],
  });

  @override
 ConsumerState<NxNxCreateView> createState() => _NxNxCreateViewState();
}

class _NxNxCreateViewState extends ConsumerState<NxNxCreateView> {
  List<NxNxTemplate> _templates = const [];
  String _tplId = '';
  NxNxTemplate? _tpl;
  final Map<String, dynamic> _values = {};

  String _outDir = '';
  bool _dirTouched = false;
  NxNxDirCheck? _dirState;
  Timer? _dirTimer;

  NxNxPreview? _preview;
  NxNxCreateResult? _result;
  bool _busy = false;
  bool _loading = true;
  String? _error;

  MnWsEndpoint get _ep => ref.read(mnWsEndpointProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _dirTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = nxNxApiOf(widget.target);
      final list = await api.templates(_ep);
      if (!mounted) return;
      setState(() {
        _templates = list;
        _loading = false;
      });
      // 模板列表就绪后自动选中第一个，省掉一次无意义的点击
      if (list.isNotEmpty && _tplId.isEmpty) {
        await _selectTemplate(list.first.id);
      }
    } on MnWsException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _selectTemplate(String id) async {
    setState(() {
      _tplId = id;
      _tpl = null;
      _values.clear();
      _preview = null;
      _result = null;
      _dirTouched = false;
      _outDir = '';
    });
    try {
      final api = nxNxApiOf(widget.target);
      final d = await api.describe(_ep, id);
      if (!mounted || _tplId != id) return;
      setState(() {
        _tpl = d.template;
        // 用默认值预填表单 —— 用户不改就能直接生成
        for (final o in d.template.options) {
          final dv = o.defaultValue;
          if (dv != null && dv != '') _values[o.name] = dv;
        }
        if (!_dirTouched) {
          _outDir = d.template.isSiblings
              ? ''
              : nxNxSuggestProjectName(d.template, _values);
        }
      });
    } on MnWsException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  void _setValue(String name, Object? v) {
    setState(() {
      _values[name] = v;
      // 输出目录默认跟着项目名走；用户自己改过就不再自动覆盖
      if (!_dirTouched) {
        _outDir = _siblingsMode ? '' : nxNxSuggestProjectName(_tpl, _values);
      }
    });
  }

  /// 项目名：由 schema 推；推不出就留空 —— 让用户自己填目录，比猜一个错名字强。
  String get _projectName => nxNxSuggestProjectName(_tpl, _values);

  /// `siblings` 模式的模板：输出目录是各个子目录的父目录，必须用户填。
  bool get _siblingsMode => _tpl?.isSiblings ?? false;

  /// 挡住生成的全部原因（缺必填 + 格式非法 + 缺输出目录）。
  List<NxNxOptionIssue> get _issues {
    final base = nxNxBlockingIssues(_tpl?.options ?? const [], _values);
    if (_siblingsMode && _outDir.isEmpty) {
      return [
        ...base,
        const NxNxOptionIssue(
          kind: 'missing',
          name: 'dir',
          label: '输出目录',
          message: 'a_<lang>/ 们的父目录（必填，空目录）',
        ),
      ];
    }
    return base;
  }

  /// 目录可用性即时检查（防抖 400ms，避免每敲一个字都打接口）。
  void _checkDir(String dir) {
    _dirTimer?.cancel();
    if (dir.isEmpty) {
      setState(() => _dirState = null);
      return;
    }
    _dirTimer = Timer(const Duration(milliseconds: 400), () async {
      try {
        final api = nxNxApiOf(widget.target);
        final r = await api.checkDir(_ep, dir);
        if (!mounted) return;
        setState(() => _dirState = r);
      } on MnWsException {
        if (mounted) setState(() => _dirState = null);
      }
    });
  }

  Future<void> _doPreview() async {
    final issues = _issues;
    if (issues.isNotEmpty) {
      _toast(nxNxDescribeIssues(issues));
      return;
    }
    setState(() => _busy = true);
    try {
      final api = nxNxApiOf(widget.target);
      final r = await api.preview(
        _ep,
        _tplId,
        values: _values,
        dir: _outDir,
      );
      if (!mounted) return;
      setState(() {
        _preview = r;
        _result = null;
      });
    } on MnWsException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doCreate() async {
    final tpl = _tpl;
    if (tpl == null) {
      _toast('请先选一个模板');
      return;
    }
    final issues = _issues;
    if (issues.isNotEmpty) {
      _toast(nxNxDescribeIssues(issues));
      return;
    }
    final ok = await _confirm(
      '确认生成',
      '将在以下目录创建 ${_preview?.count ?? '若干'} 个文件：\n$_outDir\n\n'
          '生成器不会覆盖已有内容；目录非空会被拒绝。',
    );
    if (!ok) return;

    setState(() => _busy = true);
    try {
      final api = nxNxApiOf(widget.target);
      final r = await api.create(
        _ep,
        _tplId,
        values: _values,
        dir: _outDir,
      );
      if (!mounted) return;
      setState(() {
        _result = r;
        _preview = null;
      });
      _toast('已创建 ${r.count} 个文件');
    } on MnWsException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool> _confirm(String title, String message) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('生成'),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = QuickNavBottomBar.bodyBottomReserve(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _templates.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }
    if (_templates.isEmpty) {
      return const Center(
        child: NxNxEmpty(
          '还没有可用模板',
          hint: '在目标电脑的 templates/<id>/ 下建一个（含 template.json 与 files/）',
        ),
      );
    }

    final children = <Widget>[
      _templatesBlock(),
      _formBlock(),
      _previewBlock(),
      NxNxCliHints(module: 'template', commands: widget.commands),
    ];

    return LayoutBuilder(
      builder: (ctx, c) {
        final wide = c.maxWidth >= 720;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPad),
          child: wide
              ? IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < children.length; i++) ...[
                        if (i > 0) const SizedBox(width: AppSpacing.md),
                        Expanded(child: children[i]),
                      ],
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < children.length; i++) ...[
                      if (i > 0) const SizedBox(height: AppSpacing.md),
                      children[i],
                    ],
                  ],
                ),
        );
      },
    );
  }

  Widget _templatesBlock() {
    return NxNxBlock(
      title: '模板',
      trailing: NxNxTag('${_templates.length}'),
      child: Column(
        children: _templates
            .map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: NxNxSelectableItem(
                    title: t.name,
                    subtitle: t.description,
                    selected: t.id == _tplId,
                    onTap: () => _selectTemplate(t.id),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _formBlock() {
    final tpl = _tpl;
    final split = nxNxSplitOptions(tpl?.options ?? const []);
    final issues = _issues;

    return NxNxBlock(
      title: '选项',
      trailing: _tplId.isEmpty ? null : NxNxTag(_tplId),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tpl == null)
            const NxNxEmpty('← 选一个模板')
          else ...[
            // 必填在前、可选在后：填到哪儿、还差什么，一眼能看完
            if (split.required.isNotEmpty) ...[
              _group('必填', split.required),
              const SizedBox(height: AppSpacing.md),
            ],
            if (split.optional.isNotEmpty) ...[
              _group('可选', split.optional),
              const SizedBox(height: AppSpacing.md),
            ],
            _outputDirField(),
          ],
          // 灰着的按钮必须说清自己在等什么：只禁用不解释，用户只能干瞪眼
          if (issues.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              nxNxDescribeIssues(issues),
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: EmphasisButton.borderEmphasis(
                    context,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: _busy || tpl == null || issues.isNotEmpty
                      ? null
                      : () => _doPreview(),
                  child: Text(_busy ? '处理中…' : '预览文件'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton(
                  style: EmphasisButton.borderEmphasis(
                    context,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: _busy ||
                          tpl == null ||
                          issues.isNotEmpty ||
                          _dirState?.usable == false
                      ? null
                      : () => _doCreate(),
                  child: const Text('生成项目'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _group(String title, List<NxNxOption> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: AppSpacing.xs),
            NxNxTag('${items.length}'),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        ...items.map(
          (o) => NxNxOptionField(
            option: o,
            value: _values[o.name],
            onChanged: (v) => _setValue(o.name, v),
          ),
        ),
      ],
    );
  }

  Widget _outputDirField() {
    final cs = Theme.of(context).colorScheme;
    final projectName = _projectName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('输出目录', style: TextStyle(fontSize: 12)),
            if (_siblingsMode)
              Text(' *', style: TextStyle(color: cs.error, fontSize: 12))
            else
              const NxNxTag('选填'),
          ],
        ),
        const SizedBox(height: 4),
        TextFormField(
          initialValue: _outDir,
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: AppBorderRadius.allXs,
              borderSide: BorderSide(color: cs.outlineVariant),
            ),
          ),
          onChanged: (v) {
            setState(() {
              _dirTouched = true;
              _outDir = v;
            });
            _checkDir(v);
          },
        ),
        const SizedBox(height: 4),
        Text(
          _siblingsMode
              ? 'a_<lang>/ 们的父目录（必填、空目录，生成器拒绝非空）'
              : (projectName.isNotEmpty
                  ? '留空则用项目名 $projectName（相对当前工作目录）'
                  : '留空则用模板推导的项目名'),
          style: TextStyle(fontSize: 11, color: cs.outline),
        ),
        if (_dirState != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _dirState!.usable
                  ? (_dirState!.exists ? '目录已存在但为空，可用' : '目录不存在，将新建')
                  : '目录非空（${_dirState!.entries} 项），生成器会拒绝——请换一个',
              style: TextStyle(
                fontSize: 11,
                color: _dirState!.usable ? cs.outline : cs.error,
              ),
            ),
          ),
      ],
    );
  }

  Widget _previewBlock() {
    final tpl = _tpl;
    final projectName = _projectName;
    final preview = _preview;
    final result = _result;

    // logo 预览用字母；没有 letters 的模板从项目名里取
    final letters = '${_values['letters'] ?? ''}'.isNotEmpty
        ? '${_values['letters']}'
        : projectName.replaceAll(RegExp(r'[^A-Za-z]'), '').toLowerCase().substring(
            0,
            projectName.replaceAll(RegExp(r'[^A-Za-z]'), '').toLowerCase().length < 5
                ? projectName.replaceAll(RegExp(r'[^A-Za-z]'), '').toLowerCase().length
                : 5,
          );

    return NxNxBlock(
      title: '预览',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tpl?.logo != false) ...[
            _LogoPreview(
              letters: letters,
              scheme: '${_values['scheme'] ?? 'mars'}',
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          Text(
            projectName.isEmpty ? '??' : projectName,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (preview != null) ...[
            const Divider(height: AppSpacing.lg),
            Text(
              '将创建 ${preview.count} 个文件',
              style: const TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 4),
            for (final f in preview.files)
              Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: Text(
                  f,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ),
          ],
          if (result != null) ...[
            const Divider(height: AppSpacing.lg),
            Text(
              '已创建 ${result.count} 个文件',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '下一步（复制执行）',
              style: const TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: AppBorderRadius.allXs,
              ),
              child: Text(
                result.nextSteps.join('\n'),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.6,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Logo 实时预览：内联绘制，改字母/配色立刻重绘。
///
/// scheme 的中文名与色值**只用于预览渲染**，真实取值仍以模板钩子为准 ——
/// 面板必须能在没有模板钩子的情况下画出预览，所以这里留一份展示用副本。
class _LogoPreview extends StatelessWidget {
  static const Map<String, ({String name, String bg, String fg})> _schemes = {
    'klein': (name: '克莱因蓝', bg: '#002EA6', fg: '#FFE76F'),
    'mars': (name: '马尔斯绿', bg: '#01847F', fg: '#F9D2E4'),
    'hermes': (name: '爱马仕橙', bg: '#FF770F', fg: '#000026'),
    'tiffany': (name: '蒂芙尼蓝', bg: '#80D1C8', fg: '#F8F5D6'),
    'red': (name: '中国红', bg: '#FF0000', fg: '#FAEAD3'),
    'vandyke': (name: '凡戴克棕', bg: '#492D22', fg: '#D8C7B5'),
    'prussian': (name: '普鲁士蓝', bg: '#003153', fg: '#E5DDD7'),
  };

  final String letters;
  final String scheme;

  const _LogoPreview({
    required this.letters,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    const size = 88.0;
    final s = _schemes[scheme] ?? _schemes['mars']!;
    final text = letters.length > 5 ? letters.substring(0, 5) : letters;
    final fs = (size * 0.72) / (text.isEmpty ? 1 : text.length) / 0.62;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hex(s.bg),
            borderRadius: BorderRadius.circular(size * 0.22),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _hex(s.fg),
              fontSize: fs,
              fontWeight: FontWeight.bold,
              height: 1,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${s.name} · ${s.bg}',
          style: const TextStyle(fontSize: 11),
        ),
      ],
    );
  }

  static Color _hex(String v) {
    final h = v.replaceFirst('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }
}
