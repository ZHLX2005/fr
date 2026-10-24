import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/atomic/base_empty_state.dart';
import '../ui/shell/app_notification.dart';
import 'share_receive_store.dart';

/// 外部分享接收页 —— 展示其他 app 分享给 FR 的文本/文件。
///
/// 数据来源 [ShareReceiveStore.pending]：Android ACTION_SEND/SEND_MULTIPLE
/// → MainActivity → WidgetChannel → fr://share/receive 路由 → 本页。
class ShareReceivePage extends StatelessWidget {
  const ShareReceivePage({super.key});

  @override
  Widget build(BuildContext context) {
    final data = ShareReceiveStore.pending ?? const ShareReceiveData();

    return Scaffold(
      appBar: AppBar(title: const Text('收到的分享')),
      body: data.isEmpty
          ? const BaseEmptyState(
              icon: Icons.share_outlined,
              title: '暂无分享内容',
              message: '在其他应用里选择「分享」并挑选「小豆子」即可收到内容',
              iconSize: 48,
            )
          : _ShareContent(data: data),
    );
  }
}

class _ShareContent extends StatelessWidget {
  final ShareReceiveData data;

  const _ShareContent({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = data.text;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (text != null && text.trim().isNotEmpty) ...[
          _SectionLabel('文本内容'),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  text,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: text));
                      AppNotification.show(context, '已复制到剪贴板',
                          type: AppNotificationType.success);
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('复制'),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (data.fileUris.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionLabel('文件（${data.fileUris.length}）'),
          ...data.fileUris.map((uri) => _FileTile(uri: uri)),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  final String uri;

  const _FileTile({required this.uri});

  @override
  Widget build(BuildContext context) {
    final name = uri.split('/').last;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.insert_drive_file),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(uri, maxLines: 2, overflow: TextOverflow.ellipsis),
        onTap: () {
          Clipboard.setData(ClipboardData(text: uri));
          AppNotification.show(context, '已复制文件地址',
              type: AppNotificationType.success);
        },
      ),
    );
  }
}
