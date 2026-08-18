import 'dart:io';

import 'package:flutter/material.dart';

import 'const_network.dart';
import 'network_env_models.dart';
import 'network_env_service.dart';
import 'network_widgets.dart';

/// 网络环境 Tab 卡片构建器（纯 UI，无状态依赖）
class NetworkEnvCards {
  NetworkEnvCards._();

  static Widget wifi(BuildContext context, WiFiInfo wifi) {
    return NetworkWidgets.infoCard(
      title: 'WiFi 状态',
      icon: Icons.wifi,
      color: NetworkConst.colorInfo(context),
      trailing: NetworkWidgets.statusPill(
        context,
        wifi.isConnected ? '在线' : '未连接',
        ok: wifi.isConnected,
        icon: Icons.wifi,
      ),
      children: [
        NetworkWidgets.infoRow(
          context,
          'SSID',
          NetworkEnvService.cleanSsid(wifi.ssid),
        ),
        NetworkWidgets.infoRow(context, 'BSSID', wifi.bssid ?? '未知'),
        NetworkWidgets.infoRow(context, '本地 IP', wifi.ip ?? '未知'),
        NetworkWidgets.infoRow(context, '网关', wifi.gateway ?? '未知'),
        NetworkWidgets.infoRow(context, '子网掩码', wifi.submask ?? '未知'),
        NetworkWidgets.infoRow(context, 'IPv6', wifi.ipv6 ?? '未知'),
      ],
    );
  }

  static Widget publicIp(
    BuildContext context,
    PublicIpInfo info,
    VoidCallback onRefresh,
  ) {
    return NetworkWidgets.infoCard(
      title: '公网 IP',
      icon: Icons.public,
      color: Theme.of(context).colorScheme.tertiary,
      trailing: info.loading
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              icon: Icon(Icons.refresh, size: 18),
              onPressed: onRefresh,
              tooltip: '刷新公网 IP',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
      children: [
        if (info.error != null)
          NetworkWidgets.infoRow(
            context,
            '错误',
            _sanitizeError(info.error!),
          )
        else ...[
          NetworkWidgets.infoRow(context, '公网 IP', info.ip ?? '查询中...'),
          NetworkWidgets.infoRow(context, '国家', info.country ?? '—'),
          NetworkWidgets.infoRow(context, '省份', info.region ?? '—'),
          NetworkWidgets.infoRow(context, '城市', info.city ?? '—'),
          NetworkWidgets.infoRow(context, '运营商', info.org ?? '—'),
        ],
      ],
    );
  }

  static Widget httpProbe(
    BuildContext context,
    Map<String, ProbeResult> results,
    bool testing,
    VoidCallback onRefresh,
  ) {
    return NetworkWidgets.infoCard(
      title: 'HTTP 连通性测试',
      icon: Icons.cloud_done,
      color: Theme.of(context).colorScheme.tertiary,
      trailing: testing
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              icon: Icon(Icons.refresh, size: 18),
              onPressed: onRefresh,
              tooltip: '重新测试',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
      children: NetworkConst.httpProbes.map((probe) {
        final r = results[probe.name];
        return _probeRow(context, label: probe.name, result: r);
      }).toList(),
    );
  }

  static Widget _probeRow(BuildContext context, {required String label, ProbeResult? result}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
            ),
          ),
          if (result == null)
            Text('...', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
          else ...[
            Icon(
              result.ok ? Icons.check_circle : Icons.cancel,
              color: result.ok
                  ? NetworkConst.colorSuccess(context)
                  : NetworkConst.colorError(context),
              size: 16,
            ),
            SizedBox(width: 6),
            Text(
              result.statusCode > 0 ? '${result.statusCode}' : 'fail',
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                color: result.ok
                    ? NetworkConst.colorSuccess(context)
                    : NetworkConst.colorError(context),
              ),
            ),
            Spacer(),
            Text(
              '${result.ms}ms',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Widget dns(
    BuildContext context,
    Map<String, DnsResult> results,
    bool testing,
    VoidCallback onRefresh,
  ) {
    return NetworkWidgets.infoCard(
      title: 'DNS 解析测试',
      icon: Icons.dns,
      color: Theme.of(context).colorScheme.tertiary,
      trailing: testing
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              icon: Icon(Icons.refresh, size: 18),
              onPressed: onRefresh,
              tooltip: '重新解析',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
      children: NetworkConst.dnsTestHosts.map((host) {
        final r = results[host];
        return _dnsRow(context, host: host, result: r);
      }).toList(),
    );
  }

  static Widget _dnsRow(BuildContext context, {required String host, DnsResult? result}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              host,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (result == null)
            Text('...', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
          else ...[
            Icon(
              result.ok ? Icons.check_circle : Icons.cancel,
              color: result.ok
                  ? NetworkConst.colorSuccess(context)
                  : NetworkConst.colorError(context),
              size: 16,
            ),
            SizedBox(width: 6),
            Expanded(
              child: SelectableText(
                result.ip,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  color: result.ok
                      ? NetworkConst.colorSuccess(context)
                      : NetworkConst.colorError(context),
                ),
              ),
            ),
            Text(
              '${result.ms}ms',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Widget interfaces(BuildContext context, List<NetworkInterface> ifaces) {
    if (ifaces.isEmpty) {
      return NetworkWidgets.infoCard(
        title: '网卡列表',
        icon: Icons.settings_ethernet,
        color: Theme.of(context).colorScheme.tertiary,
        children: const [Text('无可用网卡')],
      );
    }
    return NetworkWidgets.infoCard(
      title: '网卡列表 (${ifaces.length})',
      icon: Icons.settings_ethernet,
      color: Theme.of(context).colorScheme.tertiary,
      children: ifaces.map((i) => _interfaceRow(context, i)).toList(),
    );
  }

  static Widget _interfaceRow(BuildContext context, NetworkInterface iface) {
    final isLoopback = iface.name == 'lo' || iface.name == 'loopback';
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isLoopback ? Icons.loop : Icons.cable,
                size: 16,
                color: isLoopback ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.primary,
              ),
              SizedBox(width: 6),
              Text(
                iface.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              SizedBox(width: 6),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: isLoopback
                      ? Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.2)
                      : Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isLoopback ? 'Loopback' : 'Active',
                  style: TextStyle(
                    fontSize: 10,
                    color: isLoopback ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          ...iface.addresses.map((addr) {
            final isIPv4 = addr.type == InternetAddressType.IPv4;
            return Padding(
              padding: EdgeInsets.only(left: 22, top: 2, bottom: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: Text(
                      isIPv4 ? 'IPv4' : 'IPv6',
                      style: TextStyle(
                        fontSize: 10,
                        color: isIPv4 ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.tertiary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      addr.address,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  static Widget platform(BuildContext context) {
    return NetworkWidgets.infoCard(
      title: '平台信息',
      icon: Icons.computer,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      children: [
        NetworkWidgets.infoRow(context, 'hostname', Platform.localHostname),
        NetworkWidgets.infoRow(
          context,
          'OS',
          '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
          mono: false,
        ),
        NetworkWidgets.infoRow(
          context,
          'Dart 版本',
          Platform.version.split(' ').first,
        ),
        NetworkWidgets.infoRow(context, '时区', DateTime.now().timeZoneName),
      ],
    );
  }

  static Widget ports(BuildContext context) {
    return NetworkWidgets.infoCard(
      title: '常用端口参考',
      icon: Icons.numbers,
      color: Colors.deepOrange,
      children: NetworkConst.commonPorts
          .map(
            (p) => NetworkWidgets.infoRow(
              context,
              p.name,
              p.port,
              copyable: false,
            ),
          )
          .toList(),
    );
  }

  /// 简化错误信息，移除技术细节（如 SocketException 的 port、uri 等）
  static String _sanitizeError(String raw) {
    // 移除 ClientException/SocketException 前缀
    var msg = raw.replaceAll(RegExp(r'^ClientException with\s*'), '');
    // 移除 uri=... 部分
    msg = msg.replaceAll(RegExp(r',?\s*uri=[^\s,\)]+'), '');
    // 移除 port=... 部分
    msg = msg.replaceAll(RegExp(r',?\s*port=\d+'), '');
    // 移除 address=... 部分（保留地址本身用于调试）
    msg = msg.replaceAll(RegExp(r',?\s*address=[^\s,\)]+'), '');
    // 清理多余逗号和空格
    msg = msg.replaceAll(RegExp(r'^\s*,\s*'), '').trim();
    return msg.isEmpty ? '网络请求失败' : msg;
  }
}
