/// 框架事件基类（sealed class）
///
/// 所有框架事件都继承自此类，提供 sealed 层次结构以支持
/// pattern matching 穷尽性检查。
library;

part 'device_event.dart';
part 'channel_event.dart';
part 'connection_event.dart';
part 'service_event.dart';

sealed class LanEvent {
  const LanEvent();
  DateTime get timestamp => DateTime.now();
}
