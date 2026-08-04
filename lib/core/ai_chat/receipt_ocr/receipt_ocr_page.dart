import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../../services/message_strategy/factory/factory.dart';
import '../../../services/message_strategy/interfaces/interfaces.dart';
import '../../../services/message_strategy/panel/panel.dart';
import 'receipt_ocr_router.dart';

/// 小票 OCR 聊天页壳。
/// 没有输入框，只有一个「模拟识别」按钮触发假后端，
/// 结果作为 receipt_ocr 卡片 append 到全局面板。
class ReceiptOcrPage extends StatefulWidget {
  const ReceiptOcrPage({super.key});

  @override
  State<ReceiptOcrPage> createState() => _ReceiptOcrPageState();
}

class _ReceiptOcrPageState extends State<ReceiptOcrPage> {
  final ScrollController _scroll = ScrollController();
  bool _busy = false;

  late final MessagePanelController _panel =
      GetIt.instance<MessagePanelController>();
  late final MessageWidgetFactory _factory =
      GetIt.instance<MessageWidgetFactory>();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _runRecognize() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await ReceiptOcrRouter.runOnce();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('识别失败，请重试')),
      );
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final pos = _scroll.position;
        if (pos.maxScrollExtent.isFinite) {
          _scroll.animateTo(
            pos.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.tertiary;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: accent.withValues(alpha: 0.12),
              child: Icon(Icons.receipt_long, size: 18, color: accent),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('小票', style: TextStyle(fontSize: 16)),
                  Text(
                    'OCR 识别 → 快速比价',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // 顶部说明 + 触发按钮
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: accent.withValues(alpha: 0.06),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '点击右侧按钮模拟一次 OCR 识别，\n结果会作为一张交互卡 append 到下方面板。',
                    style: TextStyle(fontSize: 12, height: 1.4),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _runRecognize,
                  icon: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.document_scanner_outlined),
                  label: Text(_busy ? '识别中…' : '模拟识别'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accent,
                    backgroundColor: accent.withValues(alpha: 0.08),
                    side: BorderSide(
                        color: accent.withValues(alpha: 0.5), width: 1),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: _panel,
              builder: (context, _) {
                final messages = _panel.messages;
                if (messages.isEmpty) return _buildEmpty(theme);
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final m = messages[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _wrapBubble(theme, m.data),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _wrapBubble(ThemeData theme, IMessageData data) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.95,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(left: 12, bottom: 4),
              child: Text(
                data.type.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.tertiary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            _factory.create(context, data),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    final hintColor = theme.colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined,
                size: 44, color: hintColor.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              '面板为空',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: hintColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '点上方「模拟识别」生成一张小票卡片',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: hintColor.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}