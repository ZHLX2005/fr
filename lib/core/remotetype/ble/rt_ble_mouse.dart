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
    this.bootReportCharacteristicUuid,
    this.protocolModeCharacteristicUuid,
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

  /// Boot Mouse Input Report（0x2A33）—— Android 唯一放行的 HID 报告通道。
  final String? bootReportCharacteristicUuid;

  /// Protocol Mode（0x2A4E）—— 写 0 切 Boot 协议。
  final String? protocolModeCharacteristicUuid;

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

  /// Boot Mouse Input Report（0x2A33）：HID boot 协议下的输入报告，
  /// 布局固定为 [buttons, x(int8), y(int8), wheel(int8)] —— 不需要 Report Map。
  ///
  /// **它是 Android 唯一没封锁的 HID 报告通道**：
  /// 受限清单只含 2A4A/2A4B/2A4C/2A4D，2A33 不在内，所以订阅与读都放行。
  static const String _hogpBootMouseChar = '2a33';

  /// Protocol Mode（0x2A4E）：写 0 = Boot 协议，1 = Report 协议。
  /// 同样不在受限清单里 —— 所以「切 boot 协议」这一步是允许的。
  static const String _hogpProtocolModeChar = '2a4e';

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

  /// 轮询模式：通知订阅被系统拒绝时启用的降级通路。
  Timer? _pollTimer;
  List<int>? _lastPollBytes;
  bool _pollBusy = false;

  /// Boot 协议的两个关键特征（Android 唯一放行的 HID 报告通道）。
  BluetoothCharacteristic? _bootChar;
  BluetoothCharacteristic? _protocolModeChar;

  /// 当前实际用的传输通路（UI 展示用）。
  String _transport = '';

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

  /// 当前是否跑在**轮询模式**（通知订阅被系统拒绝后的降级通路）。
  bool get pollMode => _pollTimer != null;

  /// 当前实际使用的传输通路（空 = 尚未连上）。
  String get transportLabel => _transport;

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

      // ── 优先走 Boot 协议 ────────────────────────────────────────
      // Android 把 HID 服务（0x1812）下的 2A4A/2A4B/2A4C/2A4D 全封锁
      // （read / write / notify / descriptor 都算），但 **2A33（Boot Mouse
      // Input Report）与 2A4E（Protocol Mode）不在受限清单里**。
      // 所以：写 2A4E=0 让鼠标切到 boot 协议 → 订阅 2A33 → 拿固定 4 字节
      // 布局的报告。这一条既合规、又全速率（通知不丢帧），是唯一正解。
      if (gatt.branch == RtBleMouseBranch.hogp &&
          gatt.bootReportCharacteristicUuid != null &&
          gatt.protocolModeCharacteristicUuid != null) {
        final bootOk = await _enterBootProtocol();
        if (bootOk) {
          _layout = RtHidMouseLayout.bootMouse;
          _layoutLocked = true;
          final bootChar = _bootChar;
          if (bootChar != null) {
            _setPhase(RtBleMousePhase.subscribing);
            _log('订阅 Boot 报告特征 0x2A33…');
            try {
              await bootChar.setNotifyValue(true);
              _valueSub?.cancel();
              _valueSub = bootChar.onValueReceived.listen(_onRawReport);
              // 补一次读，确认这个特征真的有数据在动（有些设备留着 0x2A33
              // 却不更新它 —— 那就得看这行日志）
              try {
                final probe = await bootChar.read(timeout: 5);
                _log('Boot 报告首读 ${probe.length} 字节：${rtHidHex(probe)}');
              } catch (e) {
                _log('Boot 报告首读失败：$e');
              }
              _setPhase(RtBleMousePhase.ready);
              _transport = 'Boot 协议 0x2A33 通知';
              _log('已就绪（Boot 协议 / 0x2A33 通知，全速率）');
              return;
            } catch (e) {
              _log('Boot 报告订阅被拒（$e）—— 改用 read 轮询');
              if (await _startPolling(bootChar)) {
                _setPhase(RtBleMousePhase.ready);
                _transport = 'Boot 协议 0x2A33 read 轮询';
                return;
              }
            }
          }
        }
      }

      final reportChar = _reportChar;
      if (reportChar == null) {
        _setPhase(RtBleMousePhase.error);
        _log('找不到可订阅的报告特征');
        return;
      }

      _setPhase(RtBleMousePhase.subscribing);
      _log('订阅报告特征 ${gatt.reportCharacteristicUuid}…');
      try {
        await reportChar.setNotifyValue(true);
        _valueSub?.cancel();
        _valueSub = reportChar.onValueReceived.listen(_onRawReport);
        _setPhase(RtBleMousePhase.ready);
        _transport = '0x2A4D 通知';
        _log('已就绪，等待鼠标报告（通知模式）');
      } catch (e) {
        // Android 平台级封锁：第三方 App 不能订阅 HID 服务（0x1812）下的
        // Input Report 通知 —— 那需要 signature|privileged 的
        // BLUETOOTH_PRIVILEGED，普通 App 拿不到、adb 也授不了。
        // 不当作致命错误：改用 read 轮询把同一份报告拉回来。
        _log('通知订阅被系统拒绝（$e）');
        _log('降级为 read 轮询拉取报告…');
        final ok = await _startPolling(reportChar);
        if (ok) {
          _setPhase(RtBleMousePhase.ready);
          _transport = '0x2A4D read 轮询';
        } else {
          _setPhase(RtBleMousePhase.error);
          _log('结论：该设备拒绝第三方读取 HID 报告数据。');
          _log('可改用手机系统蓝牙接管鼠标 + 无障碍服务方案。');
        }
      }
    } catch (e) {
      _setPhase(RtBleMousePhase.error);
      _log('连接失败：$e');
    }
  }

  /// 写 Protocol Mode = 0，让鼠标切到 **boot 协议**。
  ///
  /// boot 协议下鼠标改用 0x2A33（Boot Mouse Input Report）上报，
  /// 布局固定 4 字节，且该特征不在 Android 的受限清单里。
  /// 写 0x2A4E 同样不受限（它的 handle 也不在 restrictedIds 里）。
  Future<bool> _enterBootProtocol() async {
    final ch = _protocolModeChar;
    if (ch == null) return false;
    // 先读一次当前模式（读 0x2A4E 也不受限），失败不致命
    try {
      if (ch.properties.read) {
        final cur = await ch.read(timeout: 5);
        _log('当前 Protocol Mode = ${cur.isEmpty ? '?' : cur.first}'
            '${cur.isEmpty ? '' : '（0=Boot / 1=Report）'}');
      }
    } catch (e) {
      _log('读 Protocol Mode 失败（可忽略）：$e');
    }
    try {
      await ch.write(<int>[0x00], withoutResponse: true);
      _log('已写入 Protocol Mode = 0（切 Boot 协议）');
      // 给设备一点时间切换协议栈
      await Future<void>.delayed(const Duration(milliseconds: 150));
      return true;
    } catch (e) {
      _log('切 Boot 协议失败：$e');
      return false;
    }
  }

  /// 轮询模式：周期性 read 报告特征，把缓存的最新报告取回来。
  ///
  /// 为什么可行：Android 封的是「**订阅**通知」（被动推送，等于窃听实时
  /// 按键流），**read**（主动拉取）走的是普通 GATT 读，只查 BLUETOOTH_CONNECT。
  ///
  /// 代价：读回来的是 peripheral 缓存的「最近一份报告」，两次轮询之间的
  /// 中间报告会丢 —— 位移会偏慢。所以这里做了**去重**（同一份报文不重复
  /// 应用，否则光标会原地狂飞），并把轮询间隔压到 16ms 尽量少丢。
  Future<bool> _startPolling(BluetoothCharacteristic ch) async {
    // 先试读一次：连读都读不到，这条路也断了，直接告诉用户。
    try {
      final probe = await ch.read(timeout: 5);
      _log('轮询首读 ${probe.length} 字节：${rtHidHex(probe)}');
    } catch (e) {
      _log('轮询首读也失败：$e');
      _log('结论：该设备拒绝第三方读取 HID 报告数据。');
      return false;
    }

    _lastPollBytes = null;
    _pollBusy = false;
    _pollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) async {
      if (_pollBusy || _disposed) return;
      _pollBusy = true;
      try {
        final v = await ch.read(timeout: 3);
        if (v.isEmpty) return;
        // 去重：同一份报文重复应用会让位移翻倍
        final last = _lastPollBytes;
        if (last != null && _sameBytes(last, v)) return;
        _lastPollBytes = List<int>.of(v);
        _onRawReport(v);
      } catch (e) {
        _log('轮询读取失败：$e');
        _pollTimer?.cancel();
        _pollTimer = null;
      } finally {
        _pollBusy = false;
      }
    });
    return true;
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 断开并清理。
  Future<void> disconnect() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _lastPollBytes = null;
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
    _pollTimer?.cancel();
    _pollTimer = null;
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
    BluetoothCharacteristic? bootReportChar;
    BluetoothCharacteristic? protocolModeChar;
    final List<BluetoothCharacteristic> reportCandidates = <BluetoothCharacteristic>[];
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
            reportCandidates.insert(0, ch);
          } else if (chUuid == _isscControlPointChar) {
            controlPointChar = ch;
          } else if (ch.properties.notify) {
            reportCandidates.add(ch);
          }
        } else if (svcUuid == _hogpService) {
          if (branch != RtBleMouseBranch.issc) {
            branch = RtBleMouseBranch.hogp;
          }
          if (chUuid == _hogpReportMapChar) {
            reportMapChar = ch;
          } else if (chUuid == _hogpBootMouseChar) {
            bootReportChar = ch;
          } else if (chUuid == _hogpProtocolModeChar) {
            protocolModeChar = ch;
          } else if (chUuid == _hogpReportChar) {
            // 0x1812 下 0x2A4D 会出现**多次**（按报告 ID 拆成输入 / 输出 /
            // 特征报告）。光看 UUID 和属性分不出来，得读 Report Reference
            // 描述符（0x2908）才知道哪个是输入报告 —— 先全收着，后面挑。
            reportCandidates.add(ch);
          }
        }
      }
    }

    // 标准 HOGP：读 Report Map，精确推导布局
    List<int> mapBytes = const <int>[];
    RtHidMouseLayout? layout;
    var inferred = false;

    if (branch == RtBleMouseBranch.hogp && reportMapChar != null) {
      try {
        mapBytes = await reportMapChar.read(timeout: 8);
        _log('Report Map 读到 ${mapBytes.length} 字节');
        layout = parseRtHidReportMap(mapBytes);
        if (layout != null) {
          _layout = layout;
          _layoutLocked = true;
          _log('布局由 Report Map 推导：${layout.label}');
        } else {
          _log('Report Map 里没有成对的 X/Y，改从样本反推');
        }
      } catch (e) {
        _log('读 Report Map 失败：$e');
      }
    }

    // 布局拿不到（ISSC 无 Report Map，或 HOGP 的 Report Map 读不了）：
    // 都交给样本反推 —— 这条路不依赖任何特权操作。
    if (layout == null) {
      inferred = true;
      _log('布局未知，将从样本反推（攒 $inferenceSampleCount 份）');
    }

    // 挑出真正的输入报告特征
    final chosen = await _pickInputReport(reportCandidates, layout, bootReportChar);
    reportChar = chosen;
    _reportChar = reportChar;
    _bootChar = bootReportChar;
    _protocolModeChar = protocolModeChar;

    if (bootReportChar != null && protocolModeChar != null) {
      _log('设备支持 Boot 协议（0x2A4E + 0x2A33）—— 走这条不受 Android 封锁');
    }

    await _probeVendorChannels(services);

    return RtBleMouseGatt(
      branch: branch,
      characteristics: infos,
      reportCharacteristicUuid: reportChar?.uuid.str.toLowerCase() ?? '-',
      reportMapCharacteristicUuid: reportMapChar?.uuid.str.toLowerCase(),
      bootReportCharacteristicUuid: bootReportChar?.uuid.str.toLowerCase(),
      protocolModeCharacteristicUuid: protocolModeChar?.uuid.str.toLowerCase(),
      controlPointCharacteristicUuid: controlPointChar?.uuid.str.toLowerCase(),
      reportMapBytes: mapBytes,
      layout: layout,
      layoutInferred: inferred,
    );
  }

  /// 在多个同名 0x2A4D 里挑出真正的**输入报告**特征。
  ///
  /// HID 服务下 0x2A4D 会按「报告 ID」拆成多个特征（输入 / 输出 / 特征），
  /// 光看 UUID 和属性分不出来 —— 必须读 **Report Reference 描述符（0x2908）**：
  /// 值是 2 字节 [reportId, reportType]，reportType 0x01=Input / 0x02=Output /
  /// 0x03=Feature。
  ///
  /// 选错的后果很具体：输出报告里装的是「鼠标回给主机的数据」，拿来当输入
  /// 报告会解出乱七八糟的位移。
  Future<BluetoothCharacteristic?> _pickInputReport(
    List<BluetoothCharacteristic> candidates,
    RtHidMouseLayout? layout,
    BluetoothCharacteristic? bootChar,
  ) async {
    if (candidates.isEmpty) {
      if (bootChar != null) _log('无 0x2A4D 候选，退回 Boot Mouse Input Report');
      return bootChar;
    }

    final refs = <BluetoothCharacteristic, _RtReportRef?>{};
    final inputs = <BluetoothCharacteristic>[];

    for (final ch in candidates) {
      final ref = await _readReportReference(ch);
      refs[ch] = ref;
      if (ref == null) {
        _log('  0x2A4D：读不到 Report Reference 描述符（0x2908）');
        continue;
      }
      _log('  0x2A4D：reportId=${ref.reportId} type=${ref.typeLabel}');
      if (ref.reportType == 0x01) inputs.add(ch);
    }

    if (inputs.isNotEmpty) {
      // 有 Report Map 的话，优先选 reportId 与描述符对得上的那个
      if (layout != null && layout.reportId >= 0) {
        for (final ch in inputs) {
          final ref = refs[ch];
          if (ref != null && ref.reportId == layout.reportId) {
            _log('选中输入报告特征：reportId=${layout.reportId}（与 Report Map 匹配）');
            return ch;
          }
        }
      }
      _log('选中输入报告特征：reportType=Input');
      return inputs.first;
    }

    // 没有 reportType=Input 的：只有输入报告才会带 CCCD（0x2902），用它兜底
    final withCccd = candidates
        .where((c) =>
            c.descriptors.any((d) => d.uuid.str.toLowerCase() == '2902'))
        .toList(growable: false);
    if (withCccd.isNotEmpty) {
      _log('按「带 CCCD」选中输入报告特征');
      return withCccd.first;
    }

    _log('没有可辨认的输入报告特征，退回第一个候选');
    return candidates.first;
  }

  /// 读 Report Reference 描述符（0x2908）→ [reportId, reportType]。
  Future<_RtReportRef?> _readReportReference(BluetoothCharacteristic ch) async {
    for (final d in ch.descriptors) {
      if (d.uuid.str.toLowerCase() != '2908') continue;
      try {
        final v = await d.read(timeout: 5);
        if (v.length < 2) return null;
        return _RtReportRef(v[0], v[1]);
      } catch (e) {
        _log('读 Report Reference 描述符失败：$e');
        return null;
      }
    }
    return null;
  }

  /// 探测厂商私有服务里的可读特征（fff0 之类）。
  ///
  /// 为什么值得探：Android 封的是 **HID 服务（0x1812）下的输入报告**；
  /// 厂商若把运动数据额外挂在**非 HID** 的服务上，那条路不受封锁。
  /// 探一次就知道有没有这种后门通道。
  Future<void> _probeVendorChannels(List<BluetoothService> services) async {
    const known = <String>{'1800', '180a', '180f', _hogpService, _isscService};
    for (final svc in services) {
      final svcUuid = svc.uuid.str.toLowerCase();
      if (known.contains(svcUuid)) continue;
      for (final ch in svc.characteristics) {
        if (!ch.properties.read) continue;
        final chUuid = ch.uuid.str.toLowerCase();
        try {
          final v = await ch.read(timeout: 5);
          if (v.isEmpty) continue;
          _log('厂商特征 $svcUuid/$chUuid → ${rtHidHex(v)}');
        } catch (e) {
          _log('厂商特征 $svcUuid/$chUuid 读取失败：$e');
        }
      }
    }
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

/// Report Reference 描述符（0x2908）的值：2 字节 [reportId, reportType]。
///
/// reportType：0x01 = Input（设备→主机的输入报告）、0x02 = Output、
/// 0x03 = Feature。
class _RtReportRef {
  const _RtReportRef(this.reportId, this.reportType);

  final int reportId;
  final int reportType;

  String get typeLabel => switch (reportType) {
        0x01 => 'Input',
        0x02 => 'Output',
        0x03 => 'Feature',
        _ => 'unknown($reportType)',
      };
}
