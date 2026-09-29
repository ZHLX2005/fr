import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../api/pi/pi.dart';
import 'pi_chat_settings.dart';

/// pi 聊天设置页 —— 配置完全在 App 内设置。
///
/// 对齐项目里 `ai_chat_settings_page.dart` 的交互（表单 + 保存按钮）。
/// 存储走 [PiChatSettings]（SharedPreferences）。
class PiChatSettingsPage extends StatefulWidget {
  final PiChatSettings? settings;

  const PiChatSettingsPage({super.key, this.settings});

  static Future<PiChatSettings> loadDefault() async =>
      PiChatSettings(await SharedPreferences.getInstance());

  @override
  State<PiChatSettingsPage> createState() => _PiChatSettingsPageState();
}

class _PiChatSettingsPageState extends State<PiChatSettingsPage> {
  /// initState 里拿不到 async prefs：先空置，_hydrate 完成后赋值。
  PiChatSettings? _settings;
  late final TextEditingController _baseUrl;
  late final TextEditingController _token;
  late final TextEditingController _cwd;
  late final TextEditingController _model;
  String _channelPrefix = kPiNginxPrefix;
  bool _obscureToken = true;
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  Future<void> _hydrate() async {
    final s = widget.settings ??
        PiChatSettings(await SharedPreferences.getInstance());
    _settings = s;
    _baseUrl.text = s.baseUrl;
    _token.text = s.token;
    _cwd.text = s.cwd;
    _model.text = s.defaultModel;
    _channelPrefix = s.channelPrefix;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _token.dispose();
    _cwd.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = _settings;
    if (s == null) return;
    await s.saveAll(
      baseUrl: _baseUrl.text,
      token: _token.text,
      cwd: _cwd.text,
      channelPrefix: _channelPrefix,
      defaultModel: _model.text,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存')),
      );
    }
  }

  /// 连通性测试：拉一次会话列表（真 token，最轻的探针）。
  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    // 先落盘再测（测试要读到最新配置）
    await _save();
    final settings = _settings;
    if (settings == null) return;
    final probe = PiSessionsEndpoint(config: () => settings.toApiConfig());
    try {
      final list = await probe.list();
      _testResult = '✓ 连通（${list.sessions.length} 个会话）';
    } on PiApiException catch (e) {
      _testResult = e.isUnauthorized
          ? '✗ token 无效（${e.statusCode}）'
          : '✗ 失败（${e.statusCode}）: ${e.message}';
    } finally {
      probe.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('pi 聊天设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _baseUrl,
            decoration: const InputDecoration(
              labelText: '服务地址',
              hintText: 'http://47.110.80.47:18080',
              helperText: 'nx-as 站点根（不带 /_nxas 前缀）',
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _token,
            obscureText: _obscureToken,
            decoration: InputDecoration(
              labelText: 'Device Token',
              hintText: 'nxas_d1.…',
              helperText: '由 nx-as device issue 签发；仅存本机',
              suffixIcon: IconButton(
                icon: Icon(_obscureToken
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () => setState(() => _obscureToken = !_obscureToken),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _cwd,
            decoration: const InputDecoration(
              labelText: '工作目录（服务端路径）',
              hintText: '/data',
              helperText: '/models 等接口必须携带；线上容器默认 /data',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _channelPrefix,
            decoration: const InputDecoration(
              labelText: '通道前缀',
              helperText: '线上 nginx 模式 = /_nxas/m/v1；本机 direct = /m/v1',
            ),
            items: [
              DropdownMenuItem(value: kPiNginxPrefix, child: Text('$kPiNginxPrefix（线上）')),
              DropdownMenuItem(value: kPiDirectPrefix, child: Text('$kPiDirectPrefix（直连）')),
            ],
            onChanged: (v) => setState(() => _channelPrefix = v ?? kPiNginxPrefix),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _model,
            decoration: const InputDecoration(
              labelText: '默认模型（可选）',
              hintText: 'provider/modelId，留空用服务端默认',
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('保存'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _testing ? null : _testConnection,
                  child: Text(_testing ? '测试中…' : '测试连通'),
                ),
              ),
            ],
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 12),
            Text(_testResult!, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 24),
          Text('说明', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            '· 模型与 provider 的配置在 pi-web 服务端设置页完成（App 只选择）。\n'
            '· token 等价于设备凭据，泄漏后可在服务端 nx-as device revoke 吊销。\n'
            '· 聊天记录存储在本机 Hive（可清空），服务端 JSONL 为完整真相。',
            style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}
