// 系统事件控制器 —— 全局单例（GetIt 注册），任何模块的后台事件
// （APK 自动下载、网络异常、Service 启动等）都通过 append() 写入这里。
// UI 侧（AI 聊天设置 → 系统消息 Tab）只需 ListenableBuilder 监听即可。
//
// 与 MessagePanelController 的区别：
//   - PanelController 是面向"交互卡"的栈（ask/selection 需要顺序消费）
//   - SystemEventsController 是面向"事件流"的日志列表（append-only，
//     可清空，不消费）
//
// 上限保护：默认 200 条；超过自动截断最早的事件，避免长时间运行内存增长。

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import '../../../services/message_strategy/interfaces/interfaces.dart';
import '../../../services/message_strategy/data/system_event_message_data.dart';

const int _kMaxEvents = 200;

/// 系统事件控制器（GetIt 单例 + ChangeNotifier）。
class SystemEventsController extends ChangeNotifier {
  SystemEventsController._();
  static final SystemEventsController _instance = SystemEventsController._();
  factory SystemEventsController() => _instance;

  final List<SystemEventMessageData> _events = [];

  /// 只读视图
  List<SystemEventMessageData> get events => List.unmodifiable(_events);
  bool get isEmpty => _events.isEmpty;
  int get length => _events.length;

  /// 把本地 DateTime 格式化成 "YYYY-MM-DDTHH:MM" 短串。
  String _formatTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)}T${two(t.hour)}:${two(t.minute)}';
  }

  /// 追加一条事件。可选 [data] 参数用于传入已构造好的 data；
  /// 不传则根据必填字段自动构造。
  void append({
    required String eventType,
    required String title,
    String? detail,
    DateTime? time,
    SystemEventMessageData? data,
  }) {
    final entry = data ??
        SystemEventMessageData(
          time: _formatTime(time ?? DateTime.now()),
          eventType: eventType,
          title: title,
          detail: detail,
        );
    _events.add(entry);
    if (_events.length > _kMaxEvents) {
      _events.removeRange(0, _events.length - _kMaxEvents);
    }
    notifyListeners();
  }

  /// 清空全部事件。
  void clear() {
    if (_events.isEmpty) return;
    _events.clear();
    notifyListeners();
  }

  /// 便利方法：从 IMessageData 列表（混合类型）过滤出系统事件。
  /// 用于把 MessagePanelController.messages 投影到系统事件列表。
  /// 当前保留为未来扩展使用；本控制器当前独立存储，不需要此方法。
  static List<SystemEventMessageData> filterFromMessages(
      Iterable<IMessageData> messages) {
    return messages
        .whereType<SystemEventMessageData>()
        .toList(growable: false);
  }
}

/// 注册到 GetIt（在 registerMessageStrategies 末尾调用，与 PanelController 一致）。
/// isRegistered 保护热重载重复注册。
void registerSystemEventsController() {
  if (!GetIt.instance.isRegistered<SystemEventsController>()) {
    GetIt.instance.registerSingleton<SystemEventsController>(
      SystemEventsController(),
    );
  }
}