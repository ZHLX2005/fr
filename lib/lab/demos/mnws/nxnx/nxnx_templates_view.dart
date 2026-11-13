import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../api/mnws/mnws.dart';
import '../../../../api/mnws/nxnx/nxnx_models.dart';
import '../../../../core/ui/global/nav/main.dart';
import '../../../../design_tokens/spacing.dart';
import '../mnws_app_views.dart';
import 'nxnx_option_form.dart';
import 'nxnx_cli_hints.dart';
import 'nxnx_page.dart';
import 'nxnx_widgets.dart';

/// 模板视图：只看不建。
///
/// 与 nx-nx 自己的「模板」面板同构（三栏：模板 / 选项 / 说明），
/// 差别只在排版：宽屏三栏并排，窄屏纵向堆叠 —— 手机上三栏并排没法看。
///
/// `describe` 的输出在这里**完整展示**，包括模板作者写的 README ——
/// 写模板的人不必再单独维护一份文档站点。
class NxNxTemplatesView extends ConsumerStatefulWidget {
  final MnWsAppTarget target;

  /// 命令表（bootstrap 下发的）—— 底下那行 CLI 等价提示由它派生。
  final List<NxNxCommand> commands;

  const NxNxTemplatesView({
    super.key,
    required this.target,
    this.commands = const [],
  });

  @override
  ConsumerState<NxNxTemplatesView> createState() => _NxNxTemplatesViewState();
}

class _NxNxTemplatesViewState extends ConsumerState<NxNxTemplatesView> {
  List<NxNxTemplate> _templates = const [];
  String? _selected;
  NxNxTemplateDetail? _detail;
  bool _loading = true;
  String? _error;

  MnWsEndpoint get _ep => ref.read(mnWsEndpointProvider);

  @override
  void initState() {
    super.initState();
    _load();
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
      if (list.isNotEmpty) {
        await _select(list.first.id);
      }
    } on MnWsException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _select(String id) async {
    setState(() {
      _selected = id;
      _detail = null;
    });
    try {
      final api = nxNxApiOf(widget.target);
      final d = await api.describe(_ep, id);
      if (!mounted || _selected != id) return;
      setState(() => _detail = d);
    } on MnWsException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
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

    final list = _templateBlock();
    final options = _optionsBlock();
    final readme = _readmeBlock();

    return LayoutBuilder(
      builder: (ctx, c) {
        final wide = c.maxWidth >= 720;
        final children = <Widget>[
          list,
          options,
          readme,
          NxNxCliHints(module: 'template', commands: widget.commands),
        ];
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

  Widget _templateBlock() {
    return NxNxBlock(
      title: '模板',
      trailing: NxNxTag('${_templates.length}'),
      child: _templates.isEmpty
          ? const NxNxEmpty('暂无模板')
          : Column(
              children: _templates
                  .map((t) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: NxNxSelectableItem(
                          title: t.name,
                          subtitle: t.description,
                          selected: t.id == _selected,
                          onTap: () => _select(t.id),
                        ),
                      ))
                  .toList(),
            ),
    );
  }

  Widget _optionsBlock() {
    final detail = _detail;
    if (detail == null) {
      return const NxNxBlock(
        title: '选项',
        child: NxNxEmpty('← 选一个模板查看'),
      );
    }
    final split = nxNxSplitOptions(detail.template.options);
    return NxNxBlock(
      title: '选项',
      trailing: NxNxTag(detail.template.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (split.required.isNotEmpty) ...[
            _optionGroup('必填', split.required),
            const SizedBox(height: AppSpacing.md),
          ],
          if (split.optional.isNotEmpty) ...[
            _optionGroup('可选', split.optional),
          ],
          if (split.required.isEmpty && split.optional.isEmpty)
            const NxNxEmpty('这个模板没有可选项'),
        ],
      ),
    );
  }

  Widget _optionGroup(String title, List<NxNxOption> items) {
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
          (o) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: NxNxKeyValue(
              label: '--${o.name}',
              value: o.label.isNotEmpty ? o.label : o.name,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  NxNxTag(o.type.isEmpty ? 'string' : o.type),
                  const SizedBox(width: 4),
                  NxNxTag(
                    o.required ? '必填' : '选填',
                    strong: o.required,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _readmeBlock() {
    final detail = _detail;
    return NxNxBlock(
      title: '说明',
      child: detail == null
          ? const NxNxEmpty('← 选一个模板查看')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.template.id,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  detail.readme.isEmpty ? '（这个模板还没有 README.md）' : detail.readme,
                  style: const TextStyle(fontSize: 12, height: 1.7),
                ),
              ],
            ),
    );
  }
}
