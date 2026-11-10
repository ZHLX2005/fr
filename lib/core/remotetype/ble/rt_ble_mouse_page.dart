// lib/core/remotetype/ble/rt_ble_mouse_page.dart
//
// 蓝牙鼠标独立页 —— RemoteType 的「临时远控鼠标」入口。
//
// ## 形态
//
// 这一页就是整个功能。用户在这里：**扫描 → 选一只鼠标 → 连上**，
// 之后手机上的物理鼠标直接接管 PC 光标。关掉本页 = 鼠标断开，
// 蓝牙主机位还给电脑。
//
// ## 与主页面的关系
//
// 页面在 RT 主页面**之上**压栈时，主页面仍然活着（Navigator 保留栈内
// widget），会话不受影响 —— 所以「先连鼠标 → 回到打字页 → 左手打字、
// 右手鼠标」是通的。反过来把本页弹掉，控制器 dispose → 鼠标断开。
//
// ## 入口
//
// 远程输入设置页里的一行。设置页是入口，本页是操作面 —— 两件事分开，
// 设置页不会被 BLE 的状态细节撑爆。

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/context/colors.dart';
import '../../../core/ui/global/nav/main.dart';
import '../../../lab/demo_session_host.dart';
import '../data/rt_constants.dart';
import '../protocol/rt_session.dart';
import 'rt_ble_mouse.dart';
import 'rt_ble_mouse_controller.dart';
import 'rt_hid_report.dart';

/// 打开蓝牙鼠标页。
Future<void> showRtBleMousePage(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const RtBleMousePage()),
  );
}

/// 蓝牙鼠标页。
class RtBleMousePage extends StatefulWidget {
  const RtBleMousePage({super.key});

  @override
  State<RtBleMousePage> createState() => _RtBleMousePageState();
}

class _RtBleMousePageState extends State<RtBleMousePage> {
  late final RtBleMouseController _ctl = RtBleMouseController(
    sessionProvider: () => demoSessionHost.get<RtSession>(kRemoteTypeDemoSlug),
  );

  RtBleMouseStatus _status = const RtBleMouseStatus(
    connected: false,
    phase: RtBleMousePhase.idle,
  );

  StreamSubscription<RtBleMouseStatus>? _statusSub;
  StreamSubscription<List<int>>? _rawSub;

  final List<List<int>> _samples = <List<int>>[];
  final List<String> _rawLines = <String>[];
  bool _diagnosticsOpen = false;

  static const int _maxSamples = 64;
  static const int _maxRawLines = 24;

  @override
  void initState() {
    super.initState();
    unawaited(_ctl.init());
    _statusSub = _ctl.status.listen((s) {
      if (!mounted) return;
      setState(() => _status = s);
    });
    _rawSub = _ctl.mouse.rawReports.listen((bytes) {
      if (!mounted) return;
      setState(() {
        _samples.add(List<int>.of(bytes));
        if (_samples.length > _maxSamples) {
          _samples.removeRange(0, _samples.length - _maxSamples);
        }
        _rawLines.add(rtHidHex(bytes));
        if (_rawLines.length > _maxRawLines) {
          _rawLines.removeRange(0, _rawLines.length - _maxRawLines);
        }
      });
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _rawSub?.cancel();
    // 页面关掉 = 鼠标断开（蓝牙主机位还给电脑）。
    unawaited(_ctl.dispose());
    super.dispose();
  }

  Future<void> _pickDevice() async {
    await _ctl.scan();
    if (!mounted) return;
    final picked = await showModalBottomSheet<RtBleMouseCandidate>(
      context: context,
      showDragHandle: true,
      builder: (_) => _DevicePickerSheet(controller: _ctl),
    );
    if (picked != null && mounted) {
      await _ctl.connect(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors.scheme;

    return Scaffold(
      appBar: const AppNavBar.standard(title: '蓝牙鼠标'),
      backgroundColor: cs.surfaceContainerHighest,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: <Widget>[
          _statusCard(cs),
          const SizedBox(height: 8),
          _deviceCard(cs),
          const SizedBox(height: 8),
          _sensitivityCard(cs),
          const SizedBox(height: 8),
          _diagnosticsCard(cs),
        ],
      ),
    );
  }

  Widget _statusCard(ColorScheme cs) {
    final connected = _status.connected;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  _status.forwarding ? Icons.check_circle : Icons.mouse,
                  color: _status.forwarding ? cs.primary : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _statusTitle(),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (connected)
                  TextButton(
                    onPressed: () => _ctl.disconnect(),
                    child: const Text('断开'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _status.message.isEmpty
                  ? '关掉本页鼠标就会断开，电脑可以立刻拿回去用。'
                  : _status.message,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            if (_status.deviceName.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                '${_status.deviceName} · ${_status.deviceId}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
            if (_status.branchLabel.isNotEmpty)
              Text(
                '分支：${_status.branchLabel}'
                '${_status.layoutLabel.isEmpty ? '' : ' · ${_status.layoutLabel}'}',
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }

  String _statusTitle() {
    if (_status.forwarding) return '鼠标已接管 PC 光标';
    if (_status.connected) return '已连接，等待会话';
    if (_status.phase == RtBleMousePhase.error) return '连接出错';
    if (_status.phase == RtBleMousePhase.scanning) return '扫描中…';
    return '未连接';
  }

  Widget _deviceCard(ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('设备', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '把鼠标从电脑上摘下来（拔接收器 / 切蓝牙通道），'
              '它才会广播，手机才扫得到。',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _pickDevice,
              icon: const Icon(Icons.bluetooth_searching),
              label: Text(
                _status.deviceName.isEmpty ? '扫描并选择鼠标' : '换一只鼠标',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sensitivityCard(ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('鼠标灵敏度', style: Theme.of(context).textTheme.titleMedium),
            Text(
              '线性系数：1.0 = 原始计数 1:1 变像素。'
              '高 DPI 鼠标觉得飞快就调小。',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            Slider(
              value: _ctl.sensitivity.clamp(
                kRtBleMouseSensitivityMin,
                kRtBleMouseSensitivityMax,
              ),
              min: kRtBleMouseSensitivityMin,
              max: kRtBleMouseSensitivityMax,
              divisions: 14,
              label: _ctl.sensitivity.toStringAsFixed(2),
              onChanged: (v) => _ctl.setSensitivity(v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _diagnosticsCard(ColorScheme cs) {
    final gatt = _ctl.mouse.gatt;
    final scored = RtHidMouseLayout.inferenceCandidates
        .map((l) => (l, scoreRtHidMouseLayout(_samples, l)))
        .where((e) => e.$2 > 0)
        .toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));

    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.troubleshoot),
        title: const Text('连接诊断'),
        subtitle: Text(
          _samples.isEmpty
              ? 'GATT 全表与鼠标报文'
              : '已收 ${_samples.length} 份报文',
        ),
        initiallyExpanded: _diagnosticsOpen,
        onExpansionChanged: (v) => _diagnosticsOpen = v,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: <Widget>[
          if (gatt == null)
            Text(
              '还没有连上设备',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            )
          else ...<Widget>[
            Text('分支：${gatt.branchLabel}',
                style: const TextStyle(fontSize: 12)),
            Text('报告特征：${gatt.reportCharacteristicUuid}',
                style: const TextStyle(fontSize: 12)),
            if (gatt.reportMapBytes.isNotEmpty)
              Text('Report Map：${rtHidHex(gatt.reportMapBytes)}',
                  style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 6),
            ...gatt.characteristics.map((c) => Text(
                  'svc ${c.serviceUuid} · chr ${c.uuid} [${c.propertiesText}]'
                  '${c.descriptorUuids.isEmpty ? '' : ' · desc ${c.descriptorUuids.join(",")}'}',
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                )),
          ],
          if (scored.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text('布局候选得分（${_samples.length} 份样本）',
                style: const TextStyle(fontSize: 12)),
            ...scored.map((e) => Text(
                  '${(e.$2 * 100).toStringAsFixed(0).padLeft(3)}%  ${e.$1.label}',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: e.$1.label == _ctl.mouse.layout?.label
                        ? cs.primary
                        : null,
                  ),
                )),
          ],
          if (_rawLines.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            const Text('最近报文', style: TextStyle(fontSize: 12)),
            ..._rawLines.reversed.take(8).map((l) => Text(
                  l,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: cs.onSurfaceVariant,
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

/// 设备选择弹层：列出扫描到的设备。
///
/// 复用**页面那一只**控制器 —— 扫描是页面发起的，弹层只负责渲染列表。
/// （另起一只控制器会扫出另一份结果，两边的「正在扫描」对不上。）
class _DevicePickerSheet extends StatefulWidget {
  const _DevicePickerSheet({required this.controller});

  final RtBleMouseController controller;

  @override
  State<_DevicePickerSheet> createState() => _DevicePickerSheetState();
}

class _DevicePickerSheetState extends State<_DevicePickerSheet> {
  List<RtBleMouseCandidate> _candidates = const <RtBleMouseCandidate>[];
  StreamSubscription<List<RtBleMouseCandidate>>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.controller.mouse.candidates.listen((list) {
      if (!mounted) return;
      setState(() => _candidates = list);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text('选择蓝牙鼠标',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              '鼠标需要处于配对模式（多数型号是长按配对键或切到蓝牙通道）。'
              '扫到的设备按信号强度排序。',
              style: TextStyle(fontSize: 12),
            ),
          ),
          if (_candidates.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 28),
              child: Text('正在扫描…'),
            )
          else
            ..._candidates.map((c) => ListTile(
                  leading: Icon(
                    c.looksLikeMouse ? Icons.mouse : Icons.bluetooth,
                    color: c.looksLikeMouse ? cs.primary : null,
                  ),
                  title: Text(c.displayName),
                  subtitle: Text('${c.id} · ${c.rssi} dBm'),
                  onTap: () => Navigator.of(context).pop(c),
                )),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
