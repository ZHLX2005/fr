import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../api/mnws/mnws.dart';
import '../../../../api/mnws/nxnx/nxnx_models.dart';
import '../../../../core/ui/global/button/main.dart';
import '../../../../core/ui/global/nav/main.dart';
import '../../../../design_tokens/radius.dart';
import '../../../../design_tokens/spacing.dart';
import '../mnws_app_views.dart';
import 'nxnx_cli_hints.dart';
import 'nxnx_page.dart';
import 'nxnx_widgets.dart';

/// 脚本工作台：列表 / 编辑 / 保存 / 运行 / 新建 / 删除。
///
/// ## 设计取舍
///
///   · 编辑器用多行输入框：零依赖、够快。要语法高亮再换 CodeMirror，
///     不影响下面的接口约定。
///   · **运行前自动保存**：用户看到的是编辑器内容，运行的也必须是它，
///     不能悄悄跑磁盘上的旧版本。
///   · 所有操作都走 [NxNxApi]（= nx-nx 自己的那套 action），
///     所以每个按钮都有等价的 CLI 命令。
class NxNxScriptsView extends ConsumerStatefulWidget {
  final MnWsAppTarget target;

  /// 命令表（bootstrap 下发的）—— 底下那行 CLI 等价提示由它派生。
  final List<NxNxCommand> commands;

  const NxNxScriptsView({
    super.key,
    required this.target,
    this.commands = const [],
  });

  @override
  ConsumerState<NxNxScriptsView> createState() => _NxNxScriptsViewState();
}

class _NxNxScriptsViewState extends ConsumerState<NxNxScriptsView> {
  List<NxNxScript> _scripts = const [];
  List<NxNxAlias> _aliases = const [];
  String? _selected;

  String _content = '';
  String _savedContent = '';
  final TextEditingController _argsCtrl = TextEditingController();
  final TextEditingController _codeCtrl = TextEditingController();

  NxNxRunResult? _runResult;
  bool _busy = false;
  String? _error;
  bool _sideTabOutput = true;

  MnWsEndpoint get _ep => ref.read(mnWsEndpointProvider);

  bool get _dirty => _content != _savedContent;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _argsCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({String? prefer}) async {
    setState(() => _error = null);
    try {
      final api = nxNxApiOf(widget.target);
      final list = await api.scripts(_ep);
      final aliases = await api.scriptAliases(_ep);
      if (!mounted) return;
      setState(() {
        _scripts = list;
        _aliases = aliases;
        final want = prefer ?? _selected;
        _selected = (want != null && list.any((s) => s.name == want))
            ? want
            : (list.isEmpty ? null : list.first.name);
      });
      await _readContent();
    } on MnWsException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  Future<void> _readContent() async {
    final name = _selected;
    if (name == null) {
      setState(() {
        _content = '';
        _savedContent = '';
        _runResult = null;
      });
      return;
    }
    setState(() => _busy = true);
    try {
      final api = nxNxApiOf(widget.target);
      final c = await api.scriptContent(_ep, name);
      if (!mounted || _selected != name) return;
      setState(() {
        _content = c;
        _savedContent = c;
        _runResult = null;
        _codeCtrl.text = c;
      });
    } on MnWsException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _save() async {
    final name = _selected;
    if (name == null || !_dirty || _busy) return false;
    setState(() => _busy = true);
    try {
      final api = nxNxApiOf(widget.target);
      await api.saveScript(_ep, name, _content);
      if (!mounted) return false;
      setState(() => _savedContent = _content);
      _toast('已保存 $name.mjs');
      return true;
    } on MnWsException catch (e) {
      _toast(e.message);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run() async {
    final name = _selected;
    if (name == null || _busy) return;
    setState(() {
      _sideTabOutput = true;
      _error = null;
      _busy = true;
    });
    try {
      // 编辑器有改动时先落盘，避免「看到的和跑的不是同一份」
      if (_dirty) {
        final api = nxNxApiOf(widget.target);
        await api.saveScript(_ep, name, _content);
        if (!mounted) return;
        setState(() => _savedContent = _content);
      }
      final api = nxNxApiOf(widget.target);
      final r = await api.runScript(_ep, name, args: _argsCtrl.text.split(' ').where((s) => s.isNotEmpty).toList());
      if (!mounted) return;
      setState(() => _runResult = r);
    } on MnWsException catch (e) {
      if (!mounted) return;
      setState(() {
        _runResult = NxNxRunResult(
          script: _selected ?? '',
          path: '',
          code: 1,
          stdout: '',
          stderr: e.message,
        );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final raw = await _prompt('新建脚本', '脚本名（不含 .mjs）');
    if (raw == null) return;
    final name = raw.trim().replaceAll(RegExp(r'\.mjs$', caseSensitive: false), '');
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      final api = nxNxApiOf(widget.target);
      final r = await api.createScript(_ep, name, _defaultTemplate(name));
      await _load(prefer: r);
      _toast('已创建 $r.mjs');
    } on MnWsException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final name = _selected;
    if (name == null) return;
    final ok = await _confirm(
      '删除脚本',
      '删除 $name.mjs 并从 manifest 移除？此操作不可撤销。',
      danger: true,
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final api = nxNxApiOf(widget.target);
      await api.deleteScript(_ep, name);
      if (!mounted) return;
      setState(() => _selected = null);
      await _load();
      _toast('已删除 $name.mjs');
    } on MnWsException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _prompt(String title, String message) async {
    final ctrl = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: AppSpacing.sm),
            TextField(controller: ctrl, autofocus: true),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return r;
  }

  Future<bool> _confirm(String title, String message, {bool danger = false}) async {
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
            child: Text(danger ? '删除' : '确定'),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 新建脚本的初始内容。
  static String _defaultTemplate(String name) => '''// $name.mjs
// 跑法：nx-nx script run $name -- <参数>

export default async function main(ctx) {
  console.log('hello from $name');
}
''';

  @override
  Widget build(BuildContext context) {
    final bottomPad = QuickNavBottomBar.bodyBottomReserve(context);

    // Ctrl/Cmd+S 保存；Ctrl/Cmd+Enter 运行
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            _save,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            _run,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _run,
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (ctx, c) {
            final wide = c.maxWidth >= 720;
            final children = <Widget>[
              _listBlock(),
              _editorBlock(),
              _sideBlock(),
              NxNxCliHints(module: 'script', commands: widget.commands),
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
        ),
      ),
    );
  }

  Widget _listBlock() {
    return NxNxBlock(
      title: '脚本',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          NxNxTag('${_scripts.length}'),
          const SizedBox(width: AppSpacing.xs),
          OutlinedButton(
            style: EmphasisButton.borderEmphasis(
              context,
              color: Theme.of(context).colorScheme.primary,
            ),
            onPressed: _busy ? null : () => _create(),
            child: const Text('新建'),
          ),
        ],
      ),
      child: _scripts.isEmpty
          ? const NxNxEmpty('暂无脚本，点「新建」开始')
          : Column(
              children: _scripts
                  .map((s) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: NxNxSelectableItem(
                          title: s.name,
                          subtitle: s.description.isEmpty ? null : s.description,
                          selected: s.name == _selected,
                          onTap: () => _selectScript(s.name),
                        ),
                      ))
                  .toList(),
            ),
    );
  }

  Future<void> _selectScript(String name) async {
    if (name == _selected) return;
    if (_dirty) {
      final ok = await _confirm(
        '有未保存的修改',
        '切换到 $name.mjs 会丢失当前修改。',
        danger: true,
      );
      if (!ok) return;
    }
    setState(() => _selected = name);
    await _readContent();
  }

  Widget _editorBlock() {
    final current = _scripts.where((s) => s.name == _selected).firstOrNull;
    final cs = Theme.of(context).colorScheme;
    return NxNxBlock(
      title: '编辑',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_dirty) const NxNxTag('未保存', strong: true),
          if (current != null)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.xs),
              child: Text(
                current.path,
                style: TextStyle(fontSize: 10, color: cs.outline),
              ),
            ),
        ],
      ),
      child: _selected == null
          ? const NxNxEmpty('← 选一个脚本')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _codeCtrl,
                  maxLines: null,
                  minLines: 12,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    height: 1.5,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: AppBorderRadius.allXs,
                      borderSide: BorderSide(color: cs.outlineVariant),
                    ),
                  ),
                  onChanged: (v) => setState(() => _content = v),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _argsCtrl,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: '运行参数（空格分隔）',
                    labelStyle: const TextStyle(fontSize: 12),
                    border: OutlineInputBorder(
                      borderRadius: AppBorderRadius.allXs,
                      borderSide: BorderSide(color: cs.outlineVariant),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: EmphasisButton.borderEmphasis(
                          context,
                          color: cs.primary,
                        ),
                        onPressed: _busy || _selected == null ? null : () => _save(),
                        child: const Text('保存'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: OutlinedButton(
                        style: EmphasisButton.borderEmphasis(
                          context,
                          color: cs.primary,
                        ),
                        onPressed: _busy || _selected == null ? null : () => _run(),
                        child: const Text('运行'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    OutlinedButton(
                      style: EmphasisButton.dangerEmphasis(context),
                      onPressed: _busy || _selected == null ? null : () => _remove(),
                      child: const Text('删除'),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _error!,
                    style: TextStyle(fontSize: 11, color: cs.error),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _sideBlock() {
    final cs = Theme.of(context).colorScheme;
    final r = _runResult;
    final groups = <String, List<NxNxAlias>>{};
    for (final a in _aliases) {
      groups.putIfAbsent(a.group, () => []).add(a);
    }

    return NxNxBlock(
      title: '输出',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          NxNxTag('输出', strong: _sideTabOutput),
          const SizedBox(width: 4),
          NxNxTag('别名 ${_aliases.length}'),
        ],
      ),
      child: _sideTabOutput
          ? (r == null
              ? const NxNxEmpty('还没有运行记录')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        NxNxTag(
                          r.ok ? 'exit ${r.code}' : 'exit ${r.code}',
                          strong: r.ok,
                          color: r.ok ? cs.primary : cs.error,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            r.path,
                            style: TextStyle(
                              fontSize: 10,
                              color: cs.outline,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (r.stdout.isNotEmpty)
                      _code(r.stdout),
                    if (r.stderr.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      if (r.stdout.isNotEmpty)
                        Text(
                          'stderr',
                          style: TextStyle(fontSize: 11, color: cs.error),
                        ),
                      _code(r.stderr),
                    ],
                  ],
                ))
          : (groups.isEmpty
              ? const NxNxEmpty('没有内置全局函数')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: groups.entries
                      .map((e) => Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e.key,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                ...e.value.map(
                                  (a) => NxNxKeyValue(
                                    label: a.name,
                                    value: a.desc,
                                  ),
                                ),
                              ],
                            ),
                          ))
                      .toList(),
                )),
    );
  }

  Widget _code(String s) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: AppBorderRadius.allXs,
        ),
        child: Text(
          s,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            height: 1.5,
          ),
        ),
      );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
