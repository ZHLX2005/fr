import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../interfaces/interfaces.dart';

/// 面板中的一条消息。
///
/// [id] 是稳定唯一标识，用于 ListView 的 Key —— 解决「同 type 多张卡」
/// 复用错乱问题（[IMessageData] 仅有 type，无法区分多张同类卡）。
class PanelMessage {
  final String id;
  final IMessageData data;

  PanelMessage({required this.id, required this.data});
}

/// 全局面板控制器（ChangeNotifier + GetIt 单例）。
///
/// 任意位置、任意时机的代码（按钮、其它流程、设置页…）都能通过
/// `GetIt.instance<MessagePanelController>()` 拿到它，向整个消息面板
/// append / removeLast / clear 卡片。面板页只需 ListenableBuilder 监听它。
///
/// 这是「用全局对象操作整个面板」的调度中枢；业务逻辑（每张卡渲染什么、
/// 流程怎么推进）仍封装在各自的 MessageWidgetStrategy / Flow 里，
/// 控制器本身只做寻址 + 路由 + 列表增删，不当业务仓库。
class MessagePanelController extends ChangeNotifier {
  final List<PanelMessage> _messages = [];
  final Uuid _uuid = const Uuid();

  /// 只读视图，避免外部直接修改列表
  List<PanelMessage> get messages => List.unmodifiable(_messages);

  bool get isEmpty => _messages.isEmpty;
  int get length => _messages.length;

  /// 追加一张卡片（自动生成唯一 id）
  void append(IMessageData data) {
    _messages.add(PanelMessage(id: _uuid.v4(), data: data));
    notifyListeners();
  }

  /// 批量追加
  void appendAll(Iterable<IMessageData> datas) {
    if (datas.isEmpty) return;
    for (final d in datas) {
      _messages.add(PanelMessage(id: _uuid.v4(), data: d));
    }
    notifyListeners();
  }

  /// 删除最后一张卡片（用于「重试 / 回退」语义）
  void removeLast() {
    if (_messages.isEmpty) return;
    _messages.removeLast();
    notifyListeners();
  }

  /// 清空面板
  void clear() {
    if (_messages.isEmpty) return;
    _messages.clear();
    notifyListeners();
  }
}
