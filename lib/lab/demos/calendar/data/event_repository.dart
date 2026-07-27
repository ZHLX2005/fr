import '../domain/event.dart';
import 'calendar_hive.dart';

/// Event 持久化（Hive Box）
class EventRepository {
  /// 读取所有事件
  List<Event> load() {
    return CalendarHive.events.values.toList();
  }

  /// 新增事件，返回带 id 的事件
  Future<Event> add(Event e) async {
    await CalendarHive.events.put(e.id, e);
    return e;
  }

  /// 更新（按 id 覆盖）
  Future<void> update(Event e) async {
    await CalendarHive.events.put(e.id, e);
  }

  /// 删除（按 id）
  Future<void> delete(String id) async {
    await CalendarHive.events.delete(id);
  }
}