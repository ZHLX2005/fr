import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'const_network.dart';
import 'network_env_cards.dart';
import 'network_env_models.dart';
import 'network_env_service.dart';

/// 网络环境 Tab —— 一站式查看当前设备的网络状态
///
/// 设计目标：让 adb logcat / 手机用户能在不打开 PC 工具的情况下
/// 直观看到网络状态，每条都可复制，便于排查问题。
class NetworkEnvTab extends StatefulWidget {
  const NetworkEnvTab({super.key});

  @override
  State<NetworkEnvTab> createState() => _NetworkEnvTabState();
}

class _NetworkEnvTabState extends State<NetworkEnvTab>
    with AutomaticKeepAliveClientMixin {
  WiFiInfo _wifi = WiFiInfo.empty;
  PublicIpInfo _publicIp = PublicIpInfo.empty;
  List<NetworkInterface> _interfaces = [];

  final Map<String, DnsResult> _dnsResults = {};
  bool _dnsTesting = false;

  final Map<String, ProbeResult> _httpProbes = {};
  bool _probeTesting = false;

  bool _loading = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final wifi = await NetworkEnvService.loadWifi();
      final ifaces = await NetworkEnvService.loadInterfaces();
      if (!mounted) return;
      setState(() {
        _wifi = wifi;
        _interfaces = ifaces;
      });
      unawaited(_refreshPublicIp());
      unawaited(_runDnsTests());
      unawaited(_runHttpProbes());
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _refreshPublicIp() async {
    if (!mounted) return;
    setState(() => _publicIp = _publicIp.copyWith(loading: true));
    final r = await NetworkEnvService.loadPublicIp();
    if (mounted) setState(() => _publicIp = r);
  }

  Future<void> _runDnsTests() async {
    if (!mounted) return;
    setState(() {
      _dnsTesting = true;
      _dnsResults.clear();
    });
    for (final host in NetworkConst.dnsTestHosts) {
      final r = await NetworkEnvService.probeDns(host);
      if (!mounted) return;
      setState(() => _dnsResults[host] = r);
    }
    if (mounted) setState(() => _dnsTesting = false);
  }

  Future<void> _runHttpProbes() async {
    if (!mounted) return;
    setState(() {
      _probeTesting = true;
      _httpProbes.clear();
    });
    final futures = NetworkConst.httpProbes.map((p) async {
      final r = await NetworkEnvService.probeHttp(p.name, p.url);
      if (mounted) setState(() => _httpProbes[p.name] = r);
    });
    await Future.wait(futures);
    if (mounted) setState(() => _probeTesting = false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '加载失败: $_error',
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          NetworkEnvCards.wifi(context, _wifi),
          const SizedBox(height: 12),
          NetworkEnvCards.publicIp(context, _publicIp, _refreshPublicIp),
          const SizedBox(height: 12),
          NetworkEnvCards.httpProbe(_httpProbes, _probeTesting, _runHttpProbes),
          const SizedBox(height: 12),
          NetworkEnvCards.dns(_dnsResults, _dnsTesting, _runDnsTests),
          const SizedBox(height: 12),
          NetworkEnvCards.interfaces(_interfaces),
          const SizedBox(height: 12),
          NetworkEnvCards.platform(context),
          const SizedBox(height: 12),
          NetworkEnvCards.ports(context),
        ],
      ),
    );
  }
}
