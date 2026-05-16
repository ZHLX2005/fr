import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'const_network.dart';

/// 网络模块公共 widgets
class NetworkWidgets {
  NetworkWidgets._();

  /// 可复制的信息行：标签 + 值（adb logcat 友好的复制功能）
  static Widget infoRow(
    BuildContext context,
    String label,
    String value, {
    bool copyable = true,
    bool mono = true,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value.isEmpty ? '—' : value,
              style: TextStyle(
                fontFamily: mono ? 'monospace' : null,
                fontSize: 13,
                color: value.isEmpty ? Colors.grey : null,
              ),
            ),
          ),
          if (copyable && value.isNotEmpty && value != '—' && value != '未知')
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _copy(context, value, label),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.copy, size: 14, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  /// 卡片：图标 + 标题 + 子内容
  static Widget infoCard({
    required String title,
    required List<Widget> children,
    IconData? icon,
    Color? color,
    Widget? trailing,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: color,
                    ),
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const Divider(),
            ...children,
          ],
        ),
      ),
    );
  }

  /// 状态徽标 (Pill)
  static Widget statusPill(
    String text, {
    required bool ok,
    IconData? icon,
  }) {
    final color = ok ? NetworkConst.colorSuccess : NetworkConst.colorError;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon ?? (ok ? Icons.check_circle : Icons.cancel),
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(color: color, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 信号强度图标 (RSSI -> icon + color)
  static Widget signalIcon(int rssi, {double size = 16}) {
    IconData icon;
    Color color;
    if (rssi > NetworkConst.rssiExcellent) {
      icon = Icons.signal_wifi_4_bar;
      color = Colors.green;
    } else if (rssi > NetworkConst.rssiGood) {
      icon = Icons.network_wifi_3_bar;
      color = Colors.lightGreen;
    } else if (rssi > NetworkConst.rssiFair) {
      icon = Icons.network_wifi_2_bar;
      color = Colors.orange;
    } else {
      icon = Icons.network_wifi_1_bar;
      color = Colors.red;
    }
    return Icon(icon, size: size, color: color);
  }

  /// 一键复制并提示
  static void _copy(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制: $label'),
        duration: const Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 时间戳: HH:mm:ss
  static String shortTime([DateTime? dt]) {
    final t = dt ?? DateTime.now();
    return t.toIso8601String().substring(11, 19);
  }
}
