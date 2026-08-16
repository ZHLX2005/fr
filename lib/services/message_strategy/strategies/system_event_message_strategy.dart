import 'package:flutter/material.dart';
import '../interfaces/interfaces.dart';
import '../data/system_event_message_data.dart';

/// 系统事件策略 —— 渲染为 IM 聊天气泡。
///
/// 渲染规约（"小助手发来一条消息"的 IM 视觉）：
///   - 左：固定圆形助手头像（机器人 icon + 灰色描边）
///   - 中：圆角气泡（左侧 flat，右侧圆 —— 模拟消息气泡），按 [eventType]
///     选主题色描边，背景为同色 8% tint
///   - 气泡内：标题加粗；详情（可选）小字浅色
///   - 气泡右上：时间戳（灰色 monospace）
///
/// 新事件类型只需在 [_iconAndColor] 加分支即可，不需要新增 strategy。
class SystemEventMessageWidgetStrategy
    extends MessageWidgetStrategy<SystemEventMessageData> {
  @override
  Widget build(BuildContext context, SystemEventMessageData data) {
    final (icon, color) = _iconAndColor(data.eventType);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧：助手头像（固定）
          const _AssistantAvatar(),
          const SizedBox(width: 10),
          // 右侧：气泡
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 2),
                  child: Row(
                    children: [
                      const Text(
                        '小助手',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        data.time,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                // 气泡本体（左侧 flat，用 CustomShape 模拟）
                CustomPaint(
                  painter: _BubblePainter(color: color),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: color.withValues(alpha: 0.35),
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, size: 18, color: color),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              if (data.detail != null &&
                                  data.detail!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  data.detail!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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

/// 助手固定头像（IM 聊天气泡左侧的圆头像）。
class _AssistantAvatar extends StatelessWidget {
  const _AssistantAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.teal.withValues(alpha: 0.45),
          width: 1.2,
        ),
      ),
      child: const Icon(Icons.smart_toy, size: 20, color: Colors.teal),
    );
  }
}

/// 气泡左下"小尾巴" —— CustomPaint 在气泡左侧画一个三角，模拟 IM 风格。
/// 当前实现：画一个 6x6 的左指小三角，颜色随气泡边框色微调。
class _BubblePainter extends CustomPainter {
  final Color color;
  _BubblePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, 12)
      ..lineTo(6, 16)
      ..lineTo(0, 20)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BubblePainter old) => old.color != color;
}