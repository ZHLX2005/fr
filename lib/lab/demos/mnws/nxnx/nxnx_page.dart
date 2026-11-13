import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../api/mnws/mnws.dart';
import '../../../../api/mnws/nxnx/nxnx_api.dart';
import '../../../../api/mnws/nxnx/nxnx_models.dart';
import '../../../../core/ui/global/button/main.dart';
import '../../../../core/ui/global/nav/main.dart';
import '../mnws_app_views.dart';

/// nx-nx（项目生成器）的整页。
///
/// 这个页面是「**只代理 API、界面原生**」的样板：
/// 数据从桥那头过来，界面是 App 自己的 Widget —— 不用在手机上再开个
/// WebView 去渲染 nx-nx 自己的前端。
///
/// 选它做第一个是因为它最简单：一个列表接口（`GET /api/templates`）就能
/// 把整条链（多 PC → 分组 → 应用识别 → 经桥取数 → 原生渲染）跑通。
class NxNxPage extends ConsumerStatefulWidget {
  final MnWsAppTarget target;

  const NxNxPage({super.key, required this.target});

  @override
  ConsumerState<NxNxPage> createState() => _NxNxPageState();
}

class _NxNxPageState extends ConsumerState<NxNxPage> {
  NxNxTemplateList? _list;
  bool _loading = true;
  String? _error;

  MnWsService get _svc => ref.read(mnWsServiceProvider);

  ColorScheme get _cs => Theme.of(context).colorScheme;

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
      // 目标 PC 带上：两台机器都跑 nx-nx 时，看的是你点的这一台
      final api = NxNxApi(pc: widget.target.bridgeId);
      final list = await api.templates(_svc);
      if (!mounted) return;
      setState(() {
        _list = list;
        _loading = false;
      });
    } on MnWsException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = QuickNavBottomBar.bodyBottomReserve(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('nx-nx 项目生成器'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '经 ${widget.target.pcName}（${widget.target.bridgeId}）· '
                '应用 ${widget.target.app}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPad),
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('拉模板失败', style: TextStyle(color: _cs.error)),
                      const SizedBox(height: 6),
                      Text(_error!, style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        style: EmphasisButton.borderEmphasis(
                          context,
                          color: _cs.primary,
                        ),
                        onPressed: () => _load(),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ),
            if (_list != null) ..._templateCards(_list!),
          ],
        ),
      ),
    );
  }

  /// 看某个模板的说明与可选项（`GET /api/templates/:id`）。
  Future<void> _showDetail(NxNxTemplate t) async {
    final api = NxNxApi(pc: widget.target.bridgeId);
    Map<String, dynamic>? detail;
    String? err;
    try {
      detail = await api.describe(_svc, t.id);
    } on MnWsException catch (e) {
      err = e.message;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.name),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: err != null
                ? Text(err, style: TextStyle(color: _cs.error))
                : Text(
                    const JsonEncoder.withIndent('  ').convert(detail),
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  List<Widget> _templateCards(NxNxTemplateList list) {
    final cards = <Widget>[];
    if (list.errors.isNotEmpty) {
      cards.add(Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('有模板不合法', style: TextStyle(color: _cs.error)),
              const SizedBox(height: 6),
              ...list.errors.map(
                (e) => Text('· $e', style: const TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ),
      ));
      cards.add(const SizedBox(height: 12));
    }
    if (list.templates.isEmpty) {
      cards.add(const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('这台机器上没有可用模板', style: TextStyle(fontSize: 12)),
        ),
      ));
      return cards;
    }
    cards.add(Card(
      child: Column(
        children: list.templates
            .map((t) => ListTile(
                  dense: true,
                  title: Text(t.name),
                  subtitle: Text(
                    t.description.isEmpty ? t.id : '${t.id} · ${t.description}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: const Icon(Icons.info_outline, size: 18),
                  // 点开看这个模板的说明与可选项 —— 走的是另一个数据接口
                  onTap: () => _showDetail(t),
                ))
            .toList(),
      ),
    ));
    return cards;
  }
}
