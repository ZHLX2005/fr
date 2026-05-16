import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'const_network.dart';
import 'network_widgets.dart';

/// WebSocket 测试 Tab
class NetworkWsTab extends StatefulWidget {
  const NetworkWsTab({super.key});

  @override
  State<NetworkWsTab> createState() => _NetworkWsTabState();
}

class _NetworkWsTabState extends State<NetworkWsTab>
    with AutomaticKeepAliveClientMixin {
  final _urlController = TextEditingController(text: NetworkConst.defaultWsUrl);
  final _messageController =
      TextEditingController(text: NetworkConst.defaultWsMessage);

  WebSocketChannel? _channel;
  final List<String> _messages = [];
  bool _connected = false;
  String _connectionStatus = '未连接';

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _urlController.dispose();
    _messageController.dispose();
    _channel?.sink.close();
    super.dispose();
  }

  void _connect() {
    try {
      final uri = Uri.parse(_urlController.text);
      _channel = WebSocketChannel.connect(uri);
      setState(() => _connectionStatus = '连接中...');

      _channel!.ready
          .then((_) {
            if (!mounted) return;
            setState(() {
              _connected = true;
              _connectionStatus = '已连接';
              _messages.add('[${NetworkWidgets.shortTime()}] 连接成功');
            });
          })
          .catchError((Object e) {
            if (!mounted) return;
            setState(() {
              _connected = false;
              _connectionStatus = '连接失败: $e';
            });
          });

      _channel!.stream.listen(
        (message) {
          if (!mounted) return;
          setState(() {
            _messages.add(
              '[${NetworkWidgets.shortTime()}] 收到: $message',
            );
          });
        },
        onError: (Object error) {
          if (!mounted) return;
          setState(() {
            _connected = false;
            _connectionStatus = '连接断开: $error';
          });
        },
        onDone: () {
          if (!mounted) return;
          setState(() {
            _connected = false;
            _connectionStatus = '连接已关闭';
          });
        },
      );
    } catch (e) {
      setState(() => _connectionStatus = '连接失败: $e');
    }
  }

  void _send() {
    if (_channel == null || !_connected) return;
    final message = _messageController.text;
    _channel!.sink.add(message);
    setState(() {
      _messages.add('[${NetworkWidgets.shortTime()}] 发送: $message');
    });
  }

  void _disconnect() {
    _channel?.sink.close();
    setState(() {
      _connected = false;
      _connectionStatus = '已断开';
      _messages.add('[${NetworkWidgets.shortTime()}] 连接已断开');
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'WebSocket URL',
                  border: OutlineInputBorder(),
                  hintText: 'wss://example.com/ws',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: NetworkWidgets.statusPill(
                      _connectionStatus,
                      ok: _connected,
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (!_connected)
                    ElevatedButton.icon(
                      onPressed: _connect,
                      icon: const Icon(Icons.link),
                      label: const Text('连接'),
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: _disconnect,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: NetworkConst.colorError,
                      ),
                      icon: const Icon(Icons.link_off),
                      label: const Text('断开'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        labelText: '发送消息',
                        border: OutlineInputBorder(),
                      ),
                      enabled: _connected,
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _connected ? _send : null,
                    icon: const Icon(Icons.send),
                    label: const Text('发送'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Text(
                    '暂无消息',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    final isSent = msg.contains('发送:');
                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSent
                            ? Colors.blue.withValues(alpha: 0.1)
                            : Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        msg,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: isSent ? Colors.blue : Colors.black87,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
