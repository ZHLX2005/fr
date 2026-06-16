import 'transport_config.dart';

/// 传输层抽象基类
///
/// 任何具体传输（UDP / HTTP）需实现 start / stop 生命周期。
/// 传输层不感知业务事件类型，只负责字节收发。
abstract class Transport {
  Transport({required this.config});
  final TransportConfig config;

  /// 启动传输层
  Future<void> start();

  /// 停止传输层
  Future<void> stop();

  /// 当前是否运行中
  bool get isRunning;
}
