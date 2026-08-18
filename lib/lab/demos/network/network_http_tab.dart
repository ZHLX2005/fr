import 'dart:async';
import '../../../widgets/context_colors.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../core/design/emphasis_button.dart';
import 'const_network.dart';

/// HTTP 请求测试 Tab
class NetworkHttpTab extends StatefulWidget {
  const NetworkHttpTab({super.key});

  @override
  State<NetworkHttpTab> createState() => _NetworkHttpTabState();
}

class _NetworkHttpTabState extends State<NetworkHttpTab>
    with AutomaticKeepAliveClientMixin {
  final _urlController =
      TextEditingController(text: NetworkConst.defaultHttpUrl);
  final _methodController = TextEditingController(text: 'GET');
  final _headersController =
      TextEditingController(text: NetworkConst.defaultHttpHeaders);
  final _bodyController = TextEditingController();

  String _result = '';
  bool _loading = false;
  int _statusCode = 0;
  Duration? _duration;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _urlController.dispose();
    _methodController.dispose();
    _headersController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _sendRequest() async {
    setState(() {
      _loading = true;
      _result = '';
      _statusCode = 0;
    });

    final sw = Stopwatch()..start();
    try {
      final uri = Uri.parse(_urlController.text);
      final method = _methodController.text.toUpperCase();

      final headers = <String, String>{};
      for (final line in _headersController.text.split('\n')) {
        final parts = line.split(':');
        if (parts.length >= 2) {
          headers[parts[0].trim()] = parts.sublist(1).join(':').trim();
        }
      }

      final client = http.Client();
      http.Response response;
      switch (method) {
        case 'GET':
          response = await client.get(uri, headers: headers);
          break;
        case 'POST':
          response =
              await client.post(uri, headers: headers, body: _bodyController.text);
          break;
        case 'PUT':
          response =
              await client.put(uri, headers: headers, body: _bodyController.text);
          break;
        case 'DELETE':
          response = await client.delete(uri, headers: headers);
          break;
        case 'PATCH':
          response = await client.patch(uri,
              headers: headers, body: _bodyController.text);
          break;
        default:
          response = await client.get(uri, headers: headers);
      }
      sw.stop();
      if (!mounted) return;
      setState(() {
        _statusCode = response.statusCode;
        _duration = sw.elapsed;
        _result = response.body;
        _loading = false;
      });
    } catch (e) {
      sw.stop();
      if (!mounted) return;
      setState(() {
        _statusCode = 0;
        _duration = sw.elapsed;
        _result = 'Error: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ok = _statusCode >= 200 && _statusCode < 300;
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'URL',
              border: OutlineInputBorder(),
              hintText: 'https://api.example.com/endpoint',
            ),
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _methodController,
                  decoration: const InputDecoration(
                    labelText: 'Method',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _headersController,
                  decoration: const InputDecoration(
                    labelText: 'Headers (每行一个)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          TextField(
            controller: _bodyController,
            decoration: const InputDecoration(
              labelText: 'Request Body (JSON)',
              border: OutlineInputBorder(),
              hintText: '{"key": "value"}',
            ),
            maxLines: 4,
          ),
          SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _loading ? null : _sendRequest,
              icon: _loading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : Icon(Icons.send),
              label: Text(_loading ? '请求中...' : '发送请求'),
              style: EmphasisButton.borderEmphasis(
                context,
                color: context.colors.accent,
              ),
            ),
          ),
          SizedBox(height: 16),
          if (_statusCode > 0 || _result.isNotEmpty) ...[
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ok
                    ? NetworkConst.colorSuccess(context).withValues(alpha: 0.1)
                    : NetworkConst.colorError(context).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: ok
                      ? NetworkConst.colorSuccess(context)
                      : NetworkConst.colorError(context),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    ok ? Icons.check_circle : Icons.error,
                    color: ok
                        ? NetworkConst.colorSuccess(context)
                        : NetworkConst.colorError(context),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Status: $_statusCode',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: ok
                          ? NetworkConst.colorSuccess(context)
                          : NetworkConst.colorError(context),
                    ),
                  ),
                  Spacer(),
                  if (_duration != null)
                    Text(
                      '${_duration!.inMilliseconds}ms',
                      style: TextStyle(
                        color: context.colors.outline,
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(height: 12),
          ],
          if (_result.isNotEmpty)
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _result,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
