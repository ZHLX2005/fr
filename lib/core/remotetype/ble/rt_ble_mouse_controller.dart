// lib/core/remotetype/ble/rt_ble_mouse_controller.dart
//
// 蓝牙鼠标控制器 —— **页面级**，生命周期跟着页面走。
//
// ## 为什么不是应用级常驻
//
// 「偶尔远控」的正确形态是**用完即断**：
//   · 页面开着 → 鼠标连着，PC 光标被接管
//   · 页面关掉 / App 退出 → 鼠标断开，**蓝牙主机位立刻还给电脑**
//
// 这不只是省电。BLE 鼠标同一时刻只有一个主机位 —— 页面关了还占着，
// 电脑上那只鼠标就用不了了。临时用完就该把位子还回去。
//
// 所以这里刻意**没有**：应用级单例、跨页面存活、App 启动自动连、
// 无限退避重连。断了就是断了，页面上点一下重连即可。
//
// 保留的只有两样持久化：灵敏度系数 + 上次选的设备 id（方便下次直接选中）。
// 它们是偏好，不是连接状态。

import 'dart:async';

import '../data/rt_constants.dart';
import '../data/rt_prefs.dart';
import '../protocol/rt_session.dart';
import 'rt_ble_mouse.dart';
import 'rt_ble_mouse_source.dart';

/// 控制器的对外状态快照（页面订阅它渲染）。
class RtBleMouseStatus {
  const RtBleMouseStatus({
    required this.connected,
    required this.phase,
    this.deviceId = '',
    this.deviceName = '',
    this.branchLabel = '',
    this.layoutLabel = '',
    this.forwarding = false,
    this.message = '',
  });

  /// BLE 链路是否已就绪（已连接并订阅了报告特征）。
  final bool connected;

  /// 连接阶段。
  final RtBleMousePhase phase;

  /// 当前设备 id（Android 上是 MAC）。
  final String deviceId;

  /// 当前设备名。
  final String deviceName;

  /// 服务分支说明（ISSC / 标准 HOGP / 未识别）。
  final String branchLabel;

  /// 当前采用的报文布局。
  final String layoutLabel;

  /// 是否正在把鼠标事件转发给 PC。
  final bool forwarding;

  /// 最近一条状态说明。
  final String message;
}

/// 页面级蓝牙鼠标控制器。
class RtBleMouseController {
  RtBleMouseController({this.sessionProvider});

  /// 取当前可用的 RT 会话；null = 还没连上电脑。
  ///
  /// 由页面从 [demoSessionHost] 取（slug = remotetype）——
  /// 页面因此不必从 RT 主页面接收会话对象，也不会因为主页面重连而拿到旧会话。
  final RtSession? Function()? sessionProvider;

  final RtBleMouse mouse = RtBleMouse();

  RtBleMouseSource? _source;
  String _deviceId = '';
  String _deviceName = '';
  double _sensitivity = kRtBleMouseSensitivityDefault;
  String _message = '';

  final StreamController<RtBleMouseStatus> _status =
      StreamController<RtBleMouseStatus>.broadcast();

  StreamSubscription<RtBleMousePhase>? _phaseSub;
  StreamSubscription<String>? _logSub;
  bool _disposed = false;

  /// 状态流。
  Stream<RtBleMouseStatus> get status => _status.stream;

  RtBleMouseStatus get currentStatus => _snapshot();

  /// 灵敏度系数（线性）。
  double get sensitivity => _sensitivity;

  /// 上次用的设备 id（页面用来在选择列表里高亮）。
  String get lastDeviceId => _deviceId;

  /// 读偏好（灵敏度 + 上次设备）。幂等。
  Future<void> init() async {
    _phaseSub = mouse.phase.listen((_) => _emit());
    _logSub = mouse.log.listen((line) {
      _message = line;
      _emit();
    });
    _deviceId = await RtPrefs.loadBleMouseDeviceId();
    _sensitivity = await RtPrefs.loadBleMouseSensitivity();
    _emit();
  }

  /// 扫描附近设备。
  Future<void> scan() => mouse.startScan(
        timeout: const Duration(milliseconds: kRtBleMouseScanTimeoutMs),
      );

  /// 连接一只鼠标并开始转发。
  Future<void> connect(RtBleMouseCandidate candidate) async {
    _deviceId = candidate.id;
    _deviceName = candidate.displayName;
    await RtPrefs.saveBleMouseDeviceId(candidate.id);
    _emit();

    await mouse.connect(candidate.device);
    if (mouse.currentPhase != RtBleMousePhase.ready) {
      _message = '连接失败（设备可能不支持 BLE HID，或已被别的设备占着）';
      _emit();
      return;
    }
    _message = '已连接';
    _emit();
    _startForwarding();
  }

  /// 主动断开（把蓝牙主机位还给电脑）。
  Future<void> disconnect() async {
    _stopForwarding();
    await mouse.disconnect();
    _message = '已断开';
    _emit();
  }

  /// 灵敏度（线性系数）。
  Future<void> setSensitivity(double value) async {
    _sensitivity = value
        .clamp(kRtBleMouseSensitivityMin, kRtBleMouseSensitivityMax)
        .toDouble();
    await RtPrefs.saveBleMouseSensitivity(_sensitivity);
    _source?.sensitivity = _sensitivity;
    _emit();
  }

  /// 释放：断开鼠标、停转发。页面 dispose 时调用。
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _stopForwarding();
    await mouse.disconnect();
    await _phaseSub?.cancel();
    await _logSub?.cancel();
    await mouse.dispose();
    await _status.close();
  }

  RtBleMouseStatus _snapshot() {
    final gatt = mouse.gatt;
    return RtBleMouseStatus(
      connected: mouse.currentPhase == RtBleMousePhase.ready,
      phase: mouse.currentPhase,
      deviceId: _deviceId,
      deviceName: _deviceName,
      branchLabel: gatt?.branchLabel ?? '',
      layoutLabel: mouse.layout?.label ?? '',
      forwarding: _source != null,
      message: _message,
    );
  }

  void _emit() {
    if (_status.isClosed) return;
    _status.add(_snapshot());
  }

  /// 开始转发：需要会话 + 链路就绪。
  void _startForwarding() {
    if (_source != null) return;
    final session = sessionProvider?.call();
    if (session == null) {
      _message = '还没连上电脑 —— 先在远程输入里连上你的 PC';
      _emit();
      return;
    }
    _source = RtBleMouseSource(
      mouse: mouse,
      session: session,
      sensitivity: _sensitivity,
    )..start();
    _message = '鼠标已接管 PC 光标';
    _emit();
  }

  void _stopForwarding() {
    _source?.stop();
    _source = null;
  }
}
