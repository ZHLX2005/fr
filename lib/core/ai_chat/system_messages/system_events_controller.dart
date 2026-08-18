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
//
// 持久化：事件 + 已读下标以 JSON 存入 SharedPreferences（异步落盘），
// 冷启动后 restore() 恢复 —— 避免"重新进入 App 后消息列表消失"。
// 竞态保护：main() 里 crash 摄入等启动钩子可能在 restore 完成前就
// append()；恢复时把磁盘上的旧事件插到已有新事件前面，不丢任何一方。

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/message_strategy/interfaces/interfaces.dart';
import '../../../services/message_strategy/data/system_event_message_data.dart';

const int _kMaxEvents = 200;
const String _kPrefsKey = 'system_events_controller.v1';
const String _kPrefsReadIndexKey = 'system_events_controller.read_index.v1';

/// 系统事件控制器（GetIt 单例 + ChangeNotifier）。
class SystemEventsController extends ChangeNotifier {
  SystemEventsController._();
  static final SystemEventsController _instance = SystemEventsController._();
  factory SystemEventsController() => _instance;

  final List<SystemEventMessageData> _events = [];

  /// 恢复任务守卫：restore() 只生效一次（重复调用直接返回同一 Future）。
  Future<void>? _restoreFuture;

  /// 用户"最后已读"事件下标（含）。当用户在消息页打开时调用
  /// [markAllRead]，未读徽章从 [_events.length - lastReadIndex] 计算。
  /// 0 表示一条都没读过。
  int _lastReadIndex = 0;

  /// 只读视图
  List<SystemEventMessageData> get events => List.unmodifiable(_events);
  bool get isEmpty => _events.isEmpty;
  int get length => _events.length;

  /// 未读事件数 = 总数 - 已读下标。
  /// 注意：append 时如果旧的 _lastReadIndex 已经被消费过，保留即可
  /// （即用户"读到"之前的状态对新事件仍然有效）。
  int get unreadCount {
    final delta = _events.length - _lastReadIndex;
    return delta < 0 ? 0 : delta;
  }

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
      // FIFO 截断最早的事件；如果截断点跨越了 _lastReadIndex，
      // 把 _lastReadIndex 同步前移，保持"未读数"语义一致。
      final drop = _events.length - _kMaxEvents;
      _events.removeRange(0, drop);
      _lastReadIndex = (_lastReadIndex - drop).clamp(0, _events.length);
    }
    _schedulePersist();
    notifyListeners();
  }

  /// 用户进入消息页阅读完毕 → 调用此方法清零未读徽章。
  void markAllRead() {
    if (_lastReadIndex == _events.length) return;
    _lastReadIndex = _events.length;
    _schedulePersist();
    notifyListeners();
  }

  /// 清空全部事件。
  void clear() {
    if (_events.isEmpty && _lastReadIndex == 0) return;
    _events.clear();
    _lastReadIndex = 0;
    _schedulePersist();
    notifyListeners();
  }

  // ---------------- 持久化 ----------------

  /// 异步落盘（fire-and-forget）。失败静默 —— 持久化是尽力而为，
  /// 不能影响主流程的 append/markAllRead。
  void _schedulePersist() {
    final count = _events.length;
    final readIx = _lastReadIndex;
    SharedPreferences.getInstance().then((prefs) {
      final raw = jsonEncode([
        for (final e in _events)
          {
            'time': e.time,
            'eventType': e.eventType,
            'title': e.title,
            'detail': e.detail,
          }
      ]);
      return prefs.setString(_kPrefsKey, raw).then((_) {
        // ignore: avoid_print
        print('[sys-event] PERSIST ok count=$count readIx=$readIx '
            'bytes=${raw.length}');
      }).then((_) => prefs.setInt(_kPrefsReadIndexKey, readIx));
    }).catchError((Object e, StackTrace st) {
      // ignore: avoid_print
      print('[sys-event] PERSIST FAIL: $e');
      return false;
    });
  }

  /// 冷启动恢复磁盘上的事件列表。
  ///
  /// 调用时机：main() 中 registerMessageStrategies() 之后（此时单例已
  /// 挂到 GetIt，启动钩子的 emit 也能落到同一实例）。
  ///
  /// 竞态保护：若在恢复完成前已有新事件 append 进来（如 crash 摄入），
  /// 把磁盘旧事件插入到它们前面，两侧都不丢。重复调用返回同一 Future。
  Future<void> restore() {
    return _restoreFuture ??= _doRestore();
  }

  Future<void> _doRestore() async {
    List<SystemEventMessageData> restored = [];
    int savedReadIndex = 0;
    String? raw;
    try {
      final prefs = await SharedPreferences.getInstance();
      // 关键诊断：读 prefs 时把 raw 字节数和 hash 都打出来，
      // —— 排查"prefs 真的没东西" vs "prefs 有但解析失败" vs "数据正确但被某处清了"
      raw = prefs.getString(_kPrefsKey);
      // ignore: avoid_print
      print('[sys-event] RESTORE rawLen=${raw?.length ?? -1}');
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        for (final item in list) {
          final map = (item as Map).cast<String, dynamic>();
          restored.add(SystemEventMessageData(
            time: map['time'] as String? ?? '',
            eventType: map['eventType'] as String? ?? '',
            title: map['title'] as String? ?? '',
            detail: map['detail'] as String?,
          ));
        }
      }
      savedReadIndex = prefs.getInt(_kPrefsReadIndexKey) ?? 0;
    } catch (e) {
      // ignore: avoid_print
      print('[sys-event] RESTORE FAIL: $e');
      return;
    }
    // ignore: avoid_print
    print('[sys-event] RESTORE parsed=${restored.length} pending=${_events.length}');
    if (restored.isEmpty) return;

    // 旧事件在前、本次会话已 append 的新事件在后；再按上限截断。
    final pending = _events;
    _events
      ..clear()
      ..addAll(restored)
      ..addAll(pending);
    if (_events.length > _kMaxEvents) {
      final drop = _events.length - _kMaxEvents;
      _events.removeRange(0, drop);
      savedReadIndex = (savedReadIndex - drop).clamp(0, _events.length);
    }
    _lastReadIndex = savedReadIndex.clamp(0, _events.length);
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

/// 公共工具 —— 外部模块快速往"小助手"IM 面板追加一条消息。
///
/// 推荐用法：任意后台事件回调、Service 回调、错误处理路径都可以
/// 一行调用，无需 import Controller 内部细节。
///
/// 调用约定：
///   - 不抛异常：GetIt 未注册 / Controller 内部错误都被 catch 并打 debugPrint
///   - 不阻塞调用方：append 是 O(1)，可放心在主流程同步调用
///   - eventType 是稳定字符串字面量（如 'auto_apk_download_started'），
///     用于策略 widget 的图标/配色 switch。新增类型只需在
///     SystemEventMessageWidgetStrategy._iconAndColor 加分支。
///
/// 示例：
/// ```dart
/// emitSystemMessage(
///   eventType: 'auto_apk_download_started',
///   title: '检测到 APK 新版本',
///   detail: '服务器时间：$time',
/// );
/// ```
void emitSystemMessage({
  required String eventType,
  required String title,
  String? detail,
  DateTime? time,
}) {
  try {
    SystemEventsController().append(
      eventType: eventType,
      title: title,
      detail: detail,
      time: time,
    );
    // 调试日志：排查"消息没出现"类 bug 时可直接看 logcat。
    // ignore: avoid_print
    print('[sys-event] $eventType | $title');
  } catch (e, st) {
    debugPrint('[sys-event] FAILED: $eventType | $e\n$st');
  }
}