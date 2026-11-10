// lib/core/remotetype/ble/rt_ble_mouse.dart
//
// BLE 鼠标连接管理器：扫描 → 连接 → 判定服务分支 → 订阅输入报告 → 解码上报。
//
// ## 为什么需要「分支」
//
// BLE 上的 HID 设备有两套互不兼容的服务布局，国产鼠标里两套都有：
//
//   · 标准 HOGP（SIG 规范）
//     Service 0x1812 / Report Map 0x2A4B / Report 0x2A4D / Protocol Mode 0x2A4E。
//     字段位置由 Report Map 描述符推导，精确。
//
//   · ISSC / TSB HID（厂商私有）
//     Service 49535343-FE7D-4AE5-8FA9-9FAFD205E455
//     Report 49535343-ACA3-481C-91EC-D85E28A60318（Notify）
//     Control Point 49535343-6DAA-4D02-ABF6-19569ACA69FE
//     没有 Report Map，布局靠预设或从样本反推。
//
// 本模块**先连上、再看它暴露了什么**，然后自动落到对应分支 —— 两条分支的
// 订阅动作其实一样（找到那个能 Notify 的报告特征 → setNotifyValue(true)），
// 差别只在「布局从哪来」：HOGP 读 Report Map，ISSC 从样本反推。
//
// ## 依赖 flutter_blue_plus
//
// 只用公开 API：startScan / connect / discoverServices / setNotifyValue /
// onValueReceived。**不碰任何系统 HID 栈**，所以不需要 root、不需要无障碍、
// 也不需要系统蓝牙设置页先把设备认成「鼠标」。

import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'rt_hid_report.dart';

/// 设备暴露的服务布局分支。
enum RtBleMouseBranch {
  /// 厂商私有 ISSC / TSB HID（小米 / Rapoo / Inphic / XISEM 一族）。
  issc,

  /// SIG 标准 HID over GATT。
  hogp,

  /// 连上了但两种布局都不匹配。
  unknown,
}

/// 连接过程阶段，探针用来显示进度。
enum RtBleMousePhase {
  idle,
  scanning,
  connecting,
  discovering,
  subscribing,
  ready,
  error,
}

/// 扫描到的一个候选设备。
class RtBleMouseCandidate {
  const RtBleMouseCandidate({
    required this.device,
    required this.name,
    required this.rssi,
    required this.advertisedServices,
    this.looksLikeMouse = false,
  });

  final BluetoothDevice device;
  final String name;
  final int rssi;

  /// 广播包里声明的服务 UUID（十六进制小写）。
  final List<String> advertisedServices;

  /// 广播里声明了已知 HID 服务 → 大概率是鼠标/键盘这类输入设备。
  ///
  /// **只作提示，绝不作为过滤条件**：ISSC 这类固件常常什么都不广播、
  /// 或者只广播自己的私有服务；按服务过滤会把它整个漏掉。
  /// 宁可多列几个设备，让用户自己认。
  final bool looksLikeMouse;

  String get id => device.remoteId.str;

  /// 名字为空时用 id 兜底 —— 很多 BLE 鼠标在 limited discoverable 模式下不广播名字。
  String get displayName => name.isEmpty ? id : name;
}

/// 一个特征的转储信息（探针展示 GATT 全表用）。
class RtBleMouseCharacteristicInfo {
  const RtBleMouseCharacteristicInfo({
    required this.serviceUuid,
    required this.uuid,
    required this.properties,
    required this.descriptorUuids,
  });

  final String serviceUuid;
  final String uuid;

  /// 特征属性（notify / write / read ...）。
  final List<String> properties;

  /// 描述符 UUID 列表（CCCD 0x2902、Report Reference 0x2908 ...）。
  final List<String> descriptorUuids;

  String get propertiesText => properties.isEmpty ? '-' : properties.join(',');
}

/// 连上之后摸清的服务布局。
class RtBleMouseGatt {
  const RtBleMouseGatt({
    required this.branch,
    required this.characteristics,
    required this.reportCharacteristicUuid,
    this.reportMapCharacteristicUuid,
    this.controlPointCharacteristicUuid,
    this.reportMapBytes = const <int>[],
    this.layout,
    this.layoutInferred = false,
  });

  final RtBleMouseBranch branch;

  /// 全部特征的转储（探针打印）。
  final List<RtBleMouseCharacteristicInfo> characteristics;

  /// 被选中订阅的输入报告特征。
  final String reportCharacteristicUuid;

  /// 标准 HOGP 的 Report Map 特征（ISSC 分支为 null）。
  final String? reportMapCharacteristicUuid;

  /// ISSC 分支的 Control Point 特征（HOGP 分支为 null）。
  final String? controlPointCharacteristicUuid;

  /// Report Map 的原始字节（读到才有）。
  final List<int> reportMapBytes;

  /// 当前采用的字段布局（ISSC 分支要等样本够了才有）。
  final RtHidMouseLayout? layout;

  /// 布局是「反推」出来的（true）还是「描述符推导」出来的（false）。
  final bool layoutInferred;

  String get branchLabel {
    switch (branch) {
      case RtBleMouseBranch.issc:
        return 'ISSC / TSB HID';
      case RtBleMouseBranch.hogp:
        return '标准 HOGP';
      case RtBleMouseBranch.unknown:
        return '未识别';
    }
  }
}

/// BLE 鼠标连接管理器。
class RtBleMouse {
  RtBleMouse({this.inferenceSampleCount = 24});

  /// ISSC 分支反推布局需要攒多少份样本。
  final int inferenceSampleCount;

  static const String _isscService = '49535343-fe7d-4ae5-8fa9-9fafd205e455';
  static const String _isscReportChar = '49535343-aca3-481c-91ec-d85e28a60318';
  static const String _isscControlPointChar = '49535343-6daa-4d02-abf6-19569aca69fe';

  static const String _hogpService = '1812';
  static const String _hogpReportMapChar = '2a4b';
  static const String _hogpReportChar = '2a4d';

  final StreamController<List<RtBleMouseCandidate>> _candidates =
      StreamController<List<RtBleMouseCandidate>>.broadcast();
  final StreamController<List<int>> _rawReports =
      StreamController<List<int>>.broadcast();
  final StreamController<RtHidMouseReport> _reports =
      StreamController<RtHidMouseReport>.broadcast();
  final StreamController<String> _logCtl = StreamController<String>.broadcast();
  final StreamController<RtBleMousePhase> _phase =
      StreamController<RtBleMousePhase>.broadcast();

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<List<int>>? _valueSub;

  final Map<String, RtBleMouseCandidate> _candidateMap =
      <String, RtBleMouseCandidate>{};

  BluetoothDevice? _device;
  BluetoothCharacteristic? _reportChar;

  RtBleMousePhase _currentPhase = RtBleMousePhase.idle;
  RtBleMouseGatt? _gatt;
  RtHidMouseLayout? _layout;

  /// ISSC 分支反推布局时攒的样本。
  final List<List<int>> _inferenceSamples = <List<int>>[];

  bool _layoutLocked = false;
  bool _disposed = false;

  /// 扫描到的候选设备流。
  Stream<List<RtBleMouseCandidate>> get candidates => _candidates.stream;

  /// 原始报告字节流（探针看 hex 用；解码前的真相）。
  Stream<List<int>> get rawReports => _rawReports.stream;

  /// 解码后的报告流。
  Stream<RtHidMouseReport> get reports => _reports.stream;

  /// 诊断日志流。
  Stream<String> get log => _logCtl.stream;

  /// 阶段流。
  Stream<RtBleMousePhase> get phase => _phase.stream;

  RtBleMousePhase get currentPhase => _currentPhase;

  RtBleMouseGatt? get gatt => _gatt;

  RtHidMouseLayout? get layout => _layout;

  BluetoothDevice? get device => _device;

  // ── 扫描 ────────────────────────────────────────────────────────────

  /// 开始扫描。
  ///
  /// **刻意不加任何过滤条件**：BLE 鼠标在配对模式下常常
  /// · 不广播名字（limited discoverable，只有 2 字节）
  /// · 不广播标准 HID 服务 UUID（ISSC 分支只广播厂商服务，甚至什么都不广播）
  /// 按名字或按服务过滤会直接把它漏掉 —— 宁可扫出 200 个设备再自己筛。
  Future<void> startScan({Duration? timeout}) async {
    if (_disposed) return;
    _candidateMap.clear();
    _candidates.add(const <RtBleMouseCandidate>[]);
    _setPhase(RtBleMousePhase.scanning);
    _log('开始扫描 BLE（无过滤）…');

    await FlutterBluePlus.startScan(timeout: timeout);

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      if (_disposed) return;
      for (final r in results) {
        final key = r.device.remoteId.str;
        final prev = _candidateMap[key];
        final adv = r.advertisementData.serviceUuids
            .map((g) => g.str.toLowerCase())
            .toList(growable: false);
        // 同名设备保留 RSSI 更强的那份
        if (prev != null && prev.rssi >= r.rssi) continue;
        _candidateMap[key] = RtBleMouseCandidate(
          device: r.device,
          name: r.device.platformName,
          rssi: r.rssi,
          advertisedServices: adv,
          looksLikeMouse: adv.any(
            (u) => u == '1812' || u.startsWith('49535343-fe7d'),
          ),
        );
      }
      final list = _candidateMap.values.toList()
        ..sort((a, b) => b.rssi.compareTo(a.rssi));
      _candidates.add(list);
    });
  }

  Future<void> stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
    await FlutterBluePlus.stopScan();
    if (_currentPhase == RtBleMousePhase.scanning) {
      _setPhase(RtBleMousePhase.idle);
    }
    _log('扫描停止');
  }

  // ── 连接 ────────────────────────────────────────────────────────────

  /// 连接并订阅输入报告。
  ///
  /// **换设备时必须先把旧的断开** —— 否则旧设备的 GATT 订阅还活着，
  /// 两个设备同时上报，事件重复（表现为 PC 光标莫名加速）。
  Future<void> connect(BluetoothDevice device) async {
    if (_disposed) return;
    await stopScan();

    final previous = _device;
    if (previous != null && previous.remoteId.str != device.remoteId.str) {
      _log('断开旧设备 ${previous.platformName}…');
      await _valueSub?.cancel();
      _valueSub = null;
      _reportChar = null;
      try {
        await previous.disconnect();
      } catch (_) {
        // 旧设备可能已经睡死/掉线：断开失败不影响连新的。
      }
    }

    _device = device;
    _gatt = null;
    _layout = null;
    _layoutLocked = false;
    _inferenceSamples.clear();

    try {
      _setPhase(RtBleMousePhase.connecting);
      _log('连接 ${device.platformName.isEmpty ? device.remoteId.str : device.platformName}…');
      await device.connect();

      _setPhase(RtBleMousePhase.discovering);
      _log('发现服务…');
      await device.discoverServices();
      final services = device.servicesList;
      _log('发现 ${services.length} 个服务');

      final gatt = await _bindGatt(services);
      _gatt = gatt;

      if (gatt.branch == RtBleMouseBranch.unknown) {
        _setPhase(RtBleMousePhase.error);
        _log('未识别到已知 HID 布局（ISSC / HOGP 都不匹配）');
        return;
      }

      _log('分支判定：${gatt.branchLabel}');
      if (gatt.reportMapBytes.isNotEmpty) {
        _log('Report Map (${gatt.reportMapBytes.length} B): ${rtHidHex(gatt.reportMapBytes)}');
      }

      final reportChar = _reportChar;
      if (reportChar == null) {
        _setPhase(RtBleMousePhase.error);
        _log('找不到可订阅的报告特征');
        return;
      }

      _setPhase(RtBleMousePhase.subscribing);
      _log('订阅报告特征 ${gatt.reportCharacteristicUuid}…');
      await reportChar.setNotifyValue(true);

      _valueSub?.cancel();
      _valueSub = reportChar.onValueReceived.listen(_onRawReport);

      _setPhase(RtBleMousePhase.ready);
      _log('已就绪，等待鼠标报告');
    } catch (e) {
      _setPhase(RtBleMousePhase.error);
      _log('连接失败：$e');
    }
  }

  /// 断开并清理。
  Future<void> disconnect() async {
    await _valueSub?.cancel();
    _valueSub = null;
    _reportChar = null;
    _device = null;
    _gatt = null;
    _layout = null;
    _layoutLocked = false;
    _inferenceSamples.clear();
    if (_currentPhase != RtBleMousePhase.idle) {
      _setPhase(RtBleMousePhase.idle);
    }
  }

  /// 手动指定布局（探针里发现反推不对时用）。
  void setLayout(RtHidMouseLayout layout) {
    _layout = layout;
    _layoutLocked = true;
    _log('手动指定布局：${layout.label}');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _scanSub?.cancel();
    await _valueSub?.cancel();
    await _candidates.close();
    await _rawReports.close();
    await _reports.close();
    await _logCtl.close();
    await _phase.close();
  }

  // ── 内部 ────────────────────────────────────────────────────────────

  void _setPhase(RtBleMousePhase p) {
    _currentPhase = p;
    if (!_phase.isClosed) _phase.add(p);
  }

  /// 记一条诊断日志（探针与排障看这条流）。
  void _log(String message) {
    if (_disposed) return;
    if (!_logCtl.isClosed) _logCtl.add(message);
  }

  /// 按暴露的服务判定分支，挑出要订阅的报告特征。
  Future<RtBleMouseGatt> _bindGatt(List<BluetoothService> services) async {
    final infos = <RtBleMouseCharacteristicInfo>[];

    BluetoothCharacteristic? reportChar;
    BluetoothCharacteristic? reportMapChar;
    BluetoothCharacteristic? controlPointChar;
    RtBleMouseBranch branch = RtBleMouseBranch.unknown;

    for (final svc in services) {
      final svcUuid = svc.uuid.str.toLowerCase();
      for (final ch in svc.characteristics) {
        final chUuid = ch.uuid.str.toLowerCase();
        final props = <String>[];
        if (ch.properties.notify) props.add('notify');
        if (ch.properties.indicate) props.add('indicate');
        if (ch.properties.read) props.add('read');
        if (ch.properties.write) props.add('write');
        if (ch.properties.writeWithoutResponse) props.add('writeWithoutResponse');
        final descs = ch.descriptors
            .map((d) => d.uuid.str.toLowerCase())
            .toList(growable: false);

        infos.add(RtBleMouseCharacteristicInfo(
          serviceUuid: svcUuid,
          uuid: chUuid,
          properties: props,
          descriptorUuids: descs,
        ));

        if (svcUuid == _isscService) {
          branch = RtBleMouseBranch.issc;
          if (chUuid == _isscReportChar) {
            reportChar = ch;
          } else if (chUuid == _isscControlPointChar) {
            controlPointChar = ch;
          } else if (ch.properties.notify && reportChar == null) {
            reportChar = ch;
          }
        } else if (svcUuid == _hogpService) {
          if (branch != RtBleMouseBranch.issc) {
            branch = RtBleMouseBranch.hogp;
          }
          if (chUuid == _hogpReportMapChar) {
            reportMapChar = ch;
          } else if (chUuid == _hogpReportChar && ch.properties.notify) {
            reportChar = ch;
          }
        }
      }
    }

    _reportChar = reportChar;

    // 标准 HOGP：读 Report Map，精确推导布局
    List<int> mapBytes = const <int>[];
    RtHidMouseLayout? layout;
    var inferred = false;

    if (branch == RtBleMouseBranch.hogp && reportMapChar != null) {
      try {
        mapBytes = await reportMapChar.read();
        layout = parseRtHidReportMap(mapBytes);
        if (layout != null) {
          _layout = layout;
          _layoutLocked = true;
          _log('布局由 Report Map 推导：${layout.label}');
        } else {
          _log('Report Map 里没有成对的 X/Y，按未知处理');
        }
      } catch (e) {
        _log('读 Report Map 失败：$e');
      }
    }

    // ISSC 分支：Report Map 读不到也没关系，后面从样本反推
    if (branch == RtBleMouseBranch.issc && layout == null) {
      inferred = true;
      _log('ISSC 分支无 Report Map，将从样本反推布局（攒 $inferenceSampleCount 份）');
    }

    return RtBleMouseGatt(
      branch: branch,
      characteristics: infos,
      reportCharacteristicUuid: reportChar?.uuid.str.toLowerCase() ?? '-',
      reportMapCharacteristicUuid: reportMapChar?.uuid.str.toLowerCase(),
      controlPointCharacteristicUuid: controlPointChar?.uuid.str.toLowerCase(),
      reportMapBytes: mapBytes,
      layout: layout,
      layoutInferred: inferred,
    );
  }

  /// 收到一份原始报告。
  void _onRawReport(List<int> bytes) {
    if (_disposed) return;
    if (!_rawReports.isClosed) _rawReports.add(bytes);

    final layout = _layout;
    if (layout != null && _layoutLocked) {
      final r = decodeRtHidMouseReport(bytes, layout);
      if (r != null && !_reports.isClosed) _reports.add(r);
      return;
    }

    // ISSC 分支：先攒样本，反推布局
    _inferenceSamples.add(List<int>.of(bytes));
    if (_inferenceSamples.length >= inferenceSampleCount) {
      final inferred = inferRtHidMouseLayout(_inferenceSamples);
      if (inferred != null) {
        _layout = inferred;
        _layoutLocked = true;
        _log('反推布局：${inferred.label}');
        // 样本重新过一遍，把攒下但还没解的补发出去
        for (final s in _inferenceSamples) {
          final r = decodeRtHidMouseReport(s, inferred);
          if (r != null && !_reports.isClosed) _reports.add(r);
        }
      } else {
        _log('样本反推失败，布局仍未知');
      }
      _inferenceSamples.clear();
    }
  }
}
