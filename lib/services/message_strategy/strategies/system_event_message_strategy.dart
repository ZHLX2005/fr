import 'package:flutter/material.dart';
import '../interfaces/interfaces.dart';
import '../data/system_event_message_data.dart';

/// 系统事件策略 —— 后台事件的只读卡片。
///
/// 渲染规约：
///   - 左侧图标 + 配色按 [eventType] switch 选择（详见 _iconAndColor）
///   - 标题加粗；时间在右上角灰色小字
///   - 详情（可选）标题下方小字
///   - 整张卡浅底色描边，配色与图标色对齐
class SystemEventMessageWidgetStrategy
    extends MessageWidgetStrategy<SystemEventMessageData> {
  @override
  Widget build(BuildContext context, SystemEventMessageData data) {
    final (icon, color) = _iconAndColor(data.eventType);
    return _SystemEventCard(
      icon: icon,
      color: color,
      data: data,
    );
  }

  @override
  SystemEventMessageData createMockData() => const SystemEventMessageData(
        time: '2026-08-16T22:30',
        eventType: 'auto_apk_check_started',
        title: '检查 APK 新版本',
        detail: '服务器上传时间：2026-08-16T14:29（本地 22:29）',
      );

  /// 事件类型 → (图标, 配色)
  static (IconData, Color) _iconAndColor(String eventType) {
    return switch (eventType) {
      'auto_apk_check_started' => (Icons.search, Colors.indigo),
      'auto_apk_check_no_update' => (Icons.check_circle_outline, Colors.grey),
      'auto_apk_download_started' => (Icons.download, Colors.blue),
      'auto_apk_download_progress' => (Icons.cloud_download, Colors.blue),
      'auto_apk_download_completed' => (Icons.check_circle, Colors.green),
      'auto_apk_download_failed' => (Icons.error_outline, Colors.red),
      'app_crash_detected' => (Icons.bug_report, Colors.red),
      _ => (Icons.info_outline, Colors.grey),
    };
  }
}

class _SystemEventCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final SystemEventMessageData data;

  const _SystemEventCard({
    required this.icon,
    required this.color,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧图标
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: color.withValues(alpha: 0.40),
                width: 1.2,
              ),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 10),
          // 右侧：标题 + 详情
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        data.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      data.time,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                if (data.detail != null && data.detail!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    data.detail!,
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}