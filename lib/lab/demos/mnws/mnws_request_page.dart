import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/mnws/mnws.dart';
import '../../../core/ui/global/button/main.dart';
import '../../../core/ui/global/nav/main.dart';
import 'mnws_app_views.dart';

/// 通用**请求台**：任意方法 / 路径 / 头 / 体，发出去看响应。
///
/// 两个用途：
///   ① **fr 不认得的应用** —— 没有专属页面时，用它照样能调（这比「不认识
///      就装死」强得多：桥是通用的，fr 认不认识这个应用，不影响能不能调它）
///   ② 独立入口 —— 想临时打一下某个接口，不必先找到那个应用
class MnWsRequestPage extends ConsumerStatefulWidget {
  /// 从某个应用点进来时带上（预填应用与目标 PC）。
  final MnWsAppTarget? target;

  const MnWsRequestPage({super.key, this.target});

  @override
  ConsumerState<MnWsRequestPage> createState() => _MnWsRequestPageState();
}

class _MnWsRequestPageState extends ConsumerState<MnWsRequestPage> {
  late final TextEditingController _methodCtrl =
      TextEditingController(text: 'GET');
  late final TextEditingController _pathCtrl =
      TextEditingController(text: '/api/ping');
  late final TextEditingController _headerCtrl = TextEditingController();
  late final TextEditingController _bodyCtrl = TextEditingController();

  String? _app;
  String? _pc;
  MnWsResponse? _response;
  bool _sending = false;
  String? _error;

  MnWsService get _svc => ref.read(mnWsServiceProvider);

  ColorScheme get _cs => Theme.of(context).colorScheme;

  @override
  void initState() {
    super.initState();
    final t = widget.target;
    if (t != null) {
      _app = t.app;
      _pc = t.bridgeId;
    }
  }

  @override
  void dispose() {
    _methodCtrl.dispose();
    _pathCtrl.dispose();
    _headerCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  /// 解析请求头：一行一个 `名: 值`。
  Map<String, String> _headers() {
    final out = <String, String>{};
    for (final line in _headerCtrl.text.split('\n')) {
      final s = line.trim();
      if (s.isEmpty) continue;
      final idx = s.indexOf(':');
      if (idx <= 0) continue;
      out[s.substring(0, idx).trim()] = s.substring(idx + 1).trim();
    }
    return out;
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final res = await _svc.request(
        method: _methodCtrl.text.trim().isEmpty ? 'GET' : _methodCtrl.text.trim(),
        path: _pathCtrl.text.trim(),
        app: _app,
        pc: _pc,
        headers: _headers(),
        body: _bodyCtrl.text.trim().isEmpty ? null : _bodyCtrl.text,
      );
      if (!mounted) return;
      setState(() => _response = res);
    } on MnWsException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = QuickNavBottomBar.bodyBottomReserve(context);
    final t = widget.target;

    return Scaffold(
      appBar: AppBar(
        title: Text(t == null ? 'mn-ws 请求台' : '请求台 · ${t.app}'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPad),
        children: [
          if (t != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('目标', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Text('应用 ${t.app} · PC ${t.pcName}（${t.bridgeId}）',
                        style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 8),
                    Text(
                      '请求会带上这台 PC 的标识（X-Mn-Ws-Pc），所以打的是你点的这一台，'
                      '不是路由表当前指向的那台。',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          if (t != null) const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: _methodCtrl,
                          decoration: const InputDecoration(
                            labelText: '方法',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _pathCtrl,
                          decoration: const InputDecoration(
                            labelText: '路径（应用内部路径）',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _headerCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '请求头（一行一个「名: 值」）',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _bodyCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: '请求体',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton(
                    style: EmphasisButton.borderEmphasis(context, color: _cs.primary),
                    onPressed: _sending ? null : () => _send(),
                    child: Text(_sending ? '发送中…' : '发送'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(_error!, style: TextStyle(color: _cs.error)),
              ),
            ),
          if (_response != null) _responseCard(_response!),
        ],
      ),
    );
  }

  Widget _responseCard(MnWsResponse res) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('响应', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(width: 8),
                Text(
                  'HTTP ${res.status}',
                  style: TextStyle(
                    color: res.status < 400 ? _cs.primary : _cs.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${res.elapsed.inMilliseconds} ms',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _pretty(res.body),
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 能解析成 JSON 就美化一下，解不了就原样。
  static String _pretty(String body) {
    try {
      final j = jsonDecode(body);
      return const JsonEncoder.withIndent('  ').convert(j);
    } catch (_) {
      return body;
    }
  }
}
