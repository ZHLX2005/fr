import 'dart:async';

import 'lan_event.dart';

/// 框架事件总线（单例）
class EventBus {
  final StreamController<LanEvent> _controller =
      StreamController<LanEvent>.broadcast();
  bool _disposed = false;

  /// 发射事件
  void emit(LanEvent event) {
    if (_disposed) {
      throw StateError('EventBus 已 dispose，禁止再 emit');
    }
    _controller.add(event);
  }

  /// 订阅所有事件
  Stream<LanEvent> watchAll() {
    if (_disposed) {
      throw StateError('EventBus 已 dispose');
    }
    return _controller.stream;
  }

  /// 按类型订阅
  Stream<T> watch<T extends LanEvent>() {
    return watchAll().where((e) => e is T).cast<T>();
  }

  /// 销毁
  void dispose() {
    _disposed = true;
    _controller.close();
  }
}
